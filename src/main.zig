//! Entry point for the CV Builder interactive CLI.
//!
//! Presents a text-menu loop for managing CV data (profile, education,
//! experience, projects, skills, certifications) stored in an SQLite
//! database.  Optionally uses a local Ollama instance for AI-powered
//! content rewriting before rendering the final CV as a Typst source
//! file and compiling it to PDF.

const std = @import("std");
const Io = std.Io;
const sqlite = @import("sqlite");

const db = @import("db/mod.zig");
const models = @import("db/models.zig");
const types = @import("types.zig");
const menu = @import("cli/menu.zig");
const prompts = @import("cli/prompts.zig");
const llm = @import("llm/client.zig");
const render = @import("render/typst.zig");

const Profile = types.Profile;
const Education = types.Education;
const Experience = types.Experience;
const Project = types.Project;
const Skill = types.Skill;
const Certification = types.Certification;
const Category = types.Category;

var global_io: Io = undefined;

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const io = init.io;
    global_io = io;

    var arg_it = try init.minimal.args.iterateAllocator(arena);
    _ = arg_it.skip();
    const db_path: [:0]const u8 = if (arg_it.next()) |arg| arg else "cv.db";
    var database = try db.init(db_path);
    defer database.deinit();

    var stdout_buf: [4096]u8 = undefined;
    var stdout_fw = Io.File.Writer.init(.stdout(), io, &stdout_buf);
    const stdout = &stdout_fw.interface;

    var stdin_buf: [16384]u8 = undefined;
    var stdin_fr = Io.File.Reader.init(.stdin(), io, &stdin_buf);
    const stdin = &stdin_fr.interface;

    const ollama_ok = llm.isOllamaRunning(io);
    if (!ollama_ok) {
        try stdout.writeAll("Ollama not running — CV generation uses raw data.\n");
        try stdout.flush();
    }

    while (true) {
        try menu.showMainMenu(stdout);
        try stdout.flush();

        const choice = readByte(stdin);
        switch (choice) {
            '1' => try handleAdd(&database, io, stdin, stdout, arena, ollama_ok),
            '2' => try handleList(&database, stdin, stdout, arena),
            '3' => try handleEdit(&database, io, stdin, stdout, arena, ollama_ok),
            '4' => try handleDelete(&database, stdin, stdout, arena),
            '5' => try handleGenerate(&database, stdout, arena),
            '6' => {
                try stdout.writeAll("Goodbye!\n");
                try stdout.flush();
                break;
            },
            else => {
                try stdout.writeAll("Invalid choice.\n");
                try stdout.flush();
            },
        }
    }
}

/// Read a single byte from stdin, defaulting to `'6'` (exit) on EOF.
fn readByte(stdin: *Io.Reader) u8 {
    const line = (stdin.takeDelimiter('\n') catch return '6') orelse return '6';
    if (line.len == 0) return '6';
    return line[0];
}

/// Read a numeric index from stdin, returning `null` on empty input.
fn readIndex(stdin: *Io.Reader) ?usize {
    const line = (stdin.takeDelimiter('\n') catch return null) orelse return null;
    const trimmed = std.mem.trim(u8, line, "\r");
    if (trimmed.len == 0) return null;
    return std.fmt.parseInt(usize, trimmed, 10) catch null;
}

fn promptCategory(stdin: *Io.Reader) ?Category {
    const ch = readByte(stdin);
    if (ch == '7') return null;
    return Category.fromChar(ch);
}

/// Prompt for a category, collect the relevant data, and insert it
/// into the database.
fn handleAdd(database: *sqlite.Db, io: Io, stdin: *Io.Reader, stdout: *Io.Writer, allocator: std.mem.Allocator, ollama_ok: bool) !void {
    try menu.showCategoryMenu(stdout);
    try stdout.flush();
    const cat = promptCategory(stdin) orelse return;

    switch (cat) {
        .profile => {
            const p = try prompts.promptProfile(allocator, stdin, stdout);
            try models.insertProfile(database, p);
            try stdout.writeAll("Profile saved.\n");
            try stdout.flush();
            if (ollama_ok) try suggestProfile(io, stdin, stdout, allocator, database, p);
        },
        .education => {
            const e = try prompts.promptEducation(allocator, stdin, stdout);
            try models.insertEducation(database, e);
            try stdout.writeAll("Education saved.\n");
            try stdout.flush();
            if (ollama_ok) try suggestEducation(io, stdin, stdout, allocator, database, e);
        },
        .experience => {
            const e = try prompts.promptExperience(allocator, stdin, stdout);
            try models.insertExperience(database, e);
            try stdout.writeAll("Experience saved.\n");
            try stdout.flush();
            if (ollama_ok) try suggestExperience(io, stdin, stdout, allocator, database, e);
        },
        .projects => {
            const p = try prompts.promptProject(allocator, stdin, stdout);
            try models.insertProject(database, p);
            try stdout.writeAll("Project saved.\n");
            try stdout.flush();
            if (ollama_ok) try suggestProject(io, stdin, stdout, allocator, database, p);
        },
        .skills => {
            const s = try prompts.promptSkill(allocator, stdin, stdout);
            try models.insertSkill(database, s);
            try stdout.writeAll("Skill saved.\n");
        },
        .certifications => {
            const c = try prompts.promptCertification(allocator, stdin, stdout);
            try models.insertCertification(database, c);
            try stdout.writeAll("Certification saved.\n");
            try stdout.flush();
            if (ollama_ok) try suggestCertification(io, stdin, stdout, allocator, database, c);
        },
    }
    try stdout.flush();
}

/// Display all entries for a chosen category.
fn handleList(database: *sqlite.Db, stdin: *Io.Reader, stdout: *Io.Writer, allocator: std.mem.Allocator) !void {
    try menu.showCategoryMenu(stdout);
    try stdout.flush();
    const cat = promptCategory(stdin) orelse return;

    switch (cat) {
        .profile => {
            if (try models.getProfile(database, allocator)) |p| {
                try stdout.print("Profile: {s}\n", .{p.full_name});
            } else {
                try stdout.writeAll("No profile.\n");
            }
        },
        .education => {
            const items = try models.getAllEducation(database, allocator);
            defer allocator.free(items);
            for (items) |e| {
                try stdout.print("  {s} – {s}\n", .{ e.institution, e.degree orelse "" });
            }
        },
        .experience => {
            const items = try models.getAllExperience(database, allocator);
            defer allocator.free(items);
            for (items) |e| {
                try stdout.print("  {s} – {s}\n", .{ e.company, e.position orelse "" });
            }
        },
        .projects => {
            const items = try models.getAllProjects(database, allocator);
            defer allocator.free(items);
            for (items) |p| {
                try stdout.print("  {s}\n", .{p.name});
            }
        },
        .skills => {
            const items = try models.getAllSkills(database, allocator);
            defer allocator.free(items);
            for (items) |s| {
                try stdout.print("  {s}: {s}\n", .{ s.category, s.skills });
            }
        },
        .certifications => {
            const items = try models.getAllCertifications(database, allocator);
            defer allocator.free(items);
            for (items) |c| {
                try stdout.print("  {s}\n", .{c.name});
            }
        },
    }
    try stdout.flush();
}

/// List, select, and update an entry for a chosen category.
fn handleEdit(database: *sqlite.Db, io: Io, stdin: *Io.Reader, stdout: *Io.Writer, allocator: std.mem.Allocator, ollama_ok: bool) !void {
    try menu.showCategoryMenu(stdout);
    try stdout.flush();
    const cat = promptCategory(stdin) orelse return;

    switch (cat) {
        .profile => {
            if (try models.getProfile(database, allocator)) |p| {
                const updated = try prompts.promptProfileForEdit(allocator, stdin, stdout, p);
                try models.updateProfile(database, updated);
                try stdout.writeAll("Profile updated.\n");
                try stdout.flush();
                if (ollama_ok) try suggestProfile(io, stdin, stdout, allocator, database, updated);
            } else {
                try stdout.writeAll("No profile. Add one first.\n");
            }
        },
        .education => try editAndSuggest(models.getAllEducation, prompts.promptEducationForEdit, models.updateEducation, llm.curateEducationEntry, suggestEducationApply, database, io, stdin, stdout, allocator, ollama_ok),
        .experience => try editAndSuggest(models.getAllExperience, prompts.promptExperienceForEdit, models.updateExperience, llm.curateExperienceEntry, suggestExperienceApply, database, io, stdin, stdout, allocator, ollama_ok),
        .projects => try editAndSuggest(models.getAllProjects, prompts.promptProjectForEdit, models.updateProject, llm.curateProjectEntry, suggestProjectApply, database, io, stdin, stdout, allocator, ollama_ok),
        .skills => try editGeneric(models.getAllSkills, prompts.promptSkillForEdit, models.updateSkill, database, stdin, stdout, allocator),
        .certifications => try editAndSuggest(models.getAllCertifications, prompts.promptCertificationForEdit, models.updateCertification, llm.curateCertificationEntry, suggestCertificationApply, database, io, stdin, stdout, allocator, ollama_ok),
    }
    try stdout.flush();
}

fn editGeneric(
    comptime getAllFn: anytype,
    comptime promptFn: anytype,
    comptime updateFn: anytype,
    database: *sqlite.Db,
    stdin: *Io.Reader,
    stdout: *Io.Writer,
    allocator: std.mem.Allocator,
) !void {
    const items = try getAllFn(database, allocator);
    defer allocator.free(items);
    if (items.len == 0) return try stdout.writeAll("No entries.\n");
    for (items, 0..) |item, i| {
        try stdout.print("{d}) {s}\n", .{ i + 1, itemLabel(item) });
    }
    try stdout.writeAll("Enter number to edit (0 to cancel): ");
    try stdout.flush();
    const idx = (readIndex(stdin) orelse 0);
    if (idx == 0 or idx > items.len) return;
    const updated = try promptFn(allocator, stdin, stdout, items[idx - 1]);
    try updateFn(database, updated);
    try stdout.writeAll("Entry updated.\n");
}

/// List, select (with confirmation), and remove an entry.
fn handleDelete(database: *sqlite.Db, stdin: *Io.Reader, stdout: *Io.Writer, allocator: std.mem.Allocator) !void {
    try menu.showCategoryMenu(stdout);
    try stdout.flush();
    const cat = promptCategory(stdin) orelse return;

    switch (cat) {
        .profile => try stdout.writeAll("Cannot delete profile.\n"),
        .education => try deleteGeneric(models.getAllEducation, models.deleteEducation, database, stdin, stdout, allocator),
        .experience => try deleteGeneric(models.getAllExperience, models.deleteExperience, database, stdin, stdout, allocator),
        .projects => try deleteGeneric(models.getAllProjects, models.deleteProject, database, stdin, stdout, allocator),
        .skills => try deleteGeneric(models.getAllSkills, models.deleteSkill, database, stdin, stdout, allocator),
        .certifications => try deleteGeneric(models.getAllCertifications, models.deleteCertification, database, stdin, stdout, allocator),
    }
    try stdout.flush();
}

fn deleteGeneric(
    comptime getAllFn: anytype,
    comptime deleteFn: anytype,
    database: *sqlite.Db,
    stdin: *Io.Reader,
    stdout: *Io.Writer,
    allocator: std.mem.Allocator,
) !void {
    const items = try getAllFn(database, allocator);
    defer allocator.free(items);
    if (items.len == 0) return try stdout.writeAll("No entries.\n");
    for (items, 0..) |item, i| {
        try stdout.print("{d}) {s}\n", .{ i + 1, itemLabel(item) });
    }
    try stdout.writeAll("Enter number to delete (0 to cancel): ");
    try stdout.flush();
    const idx = (readIndex(stdin) orelse 0);
    if (idx == 0 or idx > items.len) return;
    try stdout.print("Are you sure? (y/N): ", .{});
    try stdout.flush();
    const confirm = readByte(stdin);
    if (confirm == 'y' or confirm == 'Y') {
        try deleteFn(database, items[idx - 1].id.?);
        try stdout.writeAll("Entry deleted.\n");
    }
}

fn itemLabel(item: anytype) []const u8 {
    const T = @TypeOf(item);
    const field_name = comptime blk: {
        for (@typeInfo(T).@"struct".field_names) |name| {
            if (!std.mem.eql(u8, name, "id")) break :blk name;
        }
        unreachable;
    };
    return @field(item, field_name);
}

fn editAndSuggest(
    comptime getAllFn: anytype,
    comptime promptFn: anytype,
    comptime updateFn: anytype,
    comptime curateFn: anytype,
    comptime applyFn: anytype,
    database: *sqlite.Db,
    io: Io,
    stdin: *Io.Reader,
    stdout: *Io.Writer,
    allocator: std.mem.Allocator,
    ollama_ok: bool,
) !void {
    const items = try getAllFn(database, allocator);
    defer allocator.free(items);
    if (items.len == 0) return try stdout.writeAll("No entries.\n");
    for (items, 0..) |item, i| {
        try stdout.print("{d}) {s}\n", .{ i + 1, itemLabel(item) });
    }
    try stdout.writeAll("Enter number to edit (0 to cancel): ");
    try stdout.flush();
    const idx = (readIndex(stdin) orelse 0);
    if (idx == 0 or idx > items.len) return;
    const updated = try promptFn(allocator, stdin, stdout, items[idx - 1]);
    try updateFn(database, updated);
    try stdout.writeAll("Entry updated.\n");
    try stdout.flush();
    if (ollama_ok) {
        const curated = curateFn(io, allocator, updated) catch |err| {
            try stdout.print("  AI suggestion skipped ({}).\n", .{err});
            try stdout.flush();
            return;
        };
        if (curated) |c| {
            try applyFn(stdout, stdin, database, updated, c);
        }
    }
}

fn suggestProfile(io: Io, stdin: *Io.Reader, stdout: *Io.Writer, allocator: std.mem.Allocator, database: *sqlite.Db, p: Profile) !void {
    try stdout.writeAll("  Checking with AI...\n");
    try stdout.flush();
    const curated = llm.curateProfileEntry(io, allocator, p) catch |err| {
        try stdout.print("  AI suggestion skipped ({}).\n", .{err});
        try stdout.flush();
        return;
    };
    if (curated) |c| try suggestProfileApply(stdout, stdin, database, p, c);
}

fn suggestProfileApply(stdout: *Io.Writer, stdin: *Io.Reader, database: *sqlite.Db, p: Profile, c: llm.CuratedProfile) !void {
    var any = false;
    if (changed(p.title, c.title)) {
        try stdout.print("    Title: {s} → {s}\n", .{ displayField(p.title), c.title.? });
        any = true;
    }
    if (changed(p.summary, c.summary)) {
        try stdout.print("    Summary: {s} → {s}\n", .{ displayField(p.summary), c.summary.? });
        any = true;
    }
    if (!any) return;
    try stdout.flush();

    if (try prompts.promptYesNo(stdout, stdin, "Apply AI improvements")) {
        var updated = p;
        if (c.title) |v| updated.title = v;
        if (c.summary) |v| updated.summary = v;
        try models.updateProfile(database, updated);
        try stdout.writeAll("AI improvements saved.\n");
    }
    try stdout.flush();
}

fn suggestEducation(io: Io, stdin: *Io.Reader, stdout: *Io.Writer, allocator: std.mem.Allocator, database: *sqlite.Db, e: Education) !void {
    try stdout.writeAll("  Checking with AI...\n");
    try stdout.flush();
    const curated = llm.curateEducationEntry(io, allocator, e) catch |err| {
        try stdout.print("  AI suggestion skipped ({}).\n", .{err});
        try stdout.flush();
        return;
    };
    if (curated) |c| try suggestEducationApply(stdout, stdin, database, e, c);
}

fn suggestEducationApply(stdout: *Io.Writer, stdin: *Io.Reader, database: *sqlite.Db, e: Education, c: llm.CuratedEducation) !void {
    if (!changed(e.highlights, c.highlights)) return;
    try stdout.print("  Education: {s}\n    Highlights: {s} → {s}\n\n", .{
        displayField(e.degree),
        displayField(e.highlights),
        c.highlights.?,
    });
    try stdout.flush();
    if (try prompts.promptYesNo(stdout, stdin, "Apply AI improvements")) {
        var updated = e;
        if (c.highlights) |v| updated.highlights = v;
        try models.updateEducation(database, updated);
        try stdout.writeAll("AI improvements saved.\n");
    }
    try stdout.flush();
}

fn suggestExperience(io: Io, stdin: *Io.Reader, stdout: *Io.Writer, allocator: std.mem.Allocator, database: *sqlite.Db, e: Experience) !void {
    try stdout.writeAll("  Checking with AI...\n");
    try stdout.flush();
    const curated = llm.curateExperienceEntry(io, allocator, e) catch |err| {
        try stdout.print("  AI suggestion skipped ({}).\n", .{err});
        try stdout.flush();
        return;
    };
    if (curated) |c| try suggestExperienceApply(stdout, stdin, database, e, c);
}

fn suggestExperienceApply(stdout: *Io.Writer, stdin: *Io.Reader, database: *sqlite.Db, e: Experience, c: llm.CuratedExperience) !void {
    var first = true;
    if (changed(e.position, c.position)) {
        if (first) {
            try stdout.print("  Experience: {s} at {s}\n", .{ displayField(e.position), e.company });
            first = false;
        }
        try stdout.print("    Position: {s} → {s}\n", .{ displayField(e.position), c.position.? });
    }
    if (changed(e.description, c.description)) {
        if (first) {
            try stdout.print("  Experience: {s} at {s}\n", .{ displayField(e.position), e.company });
            first = false;
        }
        try stdout.print("    Description: {s} → {s}\n", .{ displayField(e.description), c.description.? });
    }
    if (changed(e.highlights, c.highlights)) {
        if (first) {
            try stdout.print("  Experience: {s} at {s}\n", .{ displayField(e.position), e.company });
            first = false;
        }
        try stdout.print("    Highlights: {s} → {s}\n", .{ displayField(e.highlights), c.highlights.? });
    }
    if (first) return;
    try stdout.writeAll("\n");
    try stdout.flush();
    if (try prompts.promptYesNo(stdout, stdin, "Apply AI improvements")) {
        var updated = e;
        if (c.position) |v| updated.position = v;
        if (c.description) |v| updated.description = v;
        if (c.highlights) |v| updated.highlights = v;
        try models.updateExperience(database, updated);
        try stdout.writeAll("AI improvements saved.\n");
    }
    try stdout.flush();
}

fn suggestProject(io: Io, stdin: *Io.Reader, stdout: *Io.Writer, allocator: std.mem.Allocator, database: *sqlite.Db, p: Project) !void {
    try stdout.writeAll("  Checking with AI...\n");
    try stdout.flush();
    const curated = llm.curateProjectEntry(io, allocator, p) catch |err| {
        try stdout.print("  AI suggestion skipped ({}).\n", .{err});
        try stdout.flush();
        return;
    };
    if (curated) |c| try suggestProjectApply(stdout, stdin, database, p, c);
}

fn suggestProjectApply(stdout: *Io.Writer, stdin: *Io.Reader, database: *sqlite.Db, p: Project, c: llm.CuratedProject) !void {
    var first = true;
    if (changed(p.description, c.description)) {
        if (first) {
            try stdout.print("  Project: {s}\n", .{p.name});
            first = false;
        }
        try stdout.print("    Description: {s} → {s}\n", .{ displayField(p.description), c.description.? });
    }
    if (changed(p.highlights, c.highlights)) {
        if (first) {
            try stdout.print("  Project: {s}\n", .{p.name});
            first = false;
        }
        try stdout.print("    Highlights: {s} → {s}\n", .{ displayField(p.highlights), c.highlights.? });
    }
    if (first) return;
    try stdout.writeAll("\n");
    try stdout.flush();
    if (try prompts.promptYesNo(stdout, stdin, "Apply AI improvements")) {
        var updated = p;
        if (c.description) |v| updated.description = v;
        if (c.highlights) |v| updated.highlights = v;
        try models.updateProject(database, updated);
        try stdout.writeAll("AI improvements saved.\n");
    }
    try stdout.flush();
}

fn suggestCertification(io: Io, stdin: *Io.Reader, stdout: *Io.Writer, allocator: std.mem.Allocator, database: *sqlite.Db, c: Certification) !void {
    try stdout.writeAll("  Checking with AI...\n");
    try stdout.flush();
    const curated = llm.curateCertificationEntry(io, allocator, c) catch |err| {
        try stdout.print("  AI suggestion skipped ({}).\n", .{err});
        try stdout.flush();
        return;
    };
    if (curated) |c2| try suggestCertificationApply(stdout, stdin, database, c, c2);
}

fn suggestCertificationApply(stdout: *Io.Writer, stdin: *Io.Reader, database: *sqlite.Db, cert: Certification, c: llm.CuratedCertification) !void {
    if (!changed(cert.description, c.description)) return;
    try stdout.print("  Certification: {s}\n    Description: {s} → {s}\n\n", .{
        cert.name,
        displayField(cert.description),
        c.description.?,
    });
    try stdout.flush();
    if (try prompts.promptYesNo(stdout, stdin, "Apply AI improvements")) {
        var updated = cert;
        updated.description = c.description;
        try models.updateCertification(database, updated);
        try stdout.writeAll("AI improvements saved.\n");
    }
    try stdout.flush();
}

fn handleGenerate(database: *sqlite.Db, stdout: *Io.Writer, allocator: std.mem.Allocator) !void {
    try stdout.writeAll("Generating CV...\n");
    try stdout.flush();

    const profile = try models.getProfile(database, allocator);
    const education = try models.getAllEducation(database, allocator);
    defer allocator.free(education);
    const experience = try models.getAllExperience(database, allocator);
    defer allocator.free(experience);
    const projects = try models.getAllProjects(database, allocator);
    defer allocator.free(projects);
    const skills = try models.getAllSkills(database, allocator);
    defer allocator.free(skills);
    const certifications = try models.getAllCertifications(database, allocator);
    defer allocator.free(certifications);

    const typst_source = try render.generateTypst(
        profile,
        education,
        experience,
        projects,
        skills,
        certifications,
        allocator,
    );
    defer allocator.free(typst_source);

    const cwd = std.Io.Dir.cwd();
    try cwd.writeFile(global_io, .{ .sub_path = "basic-resume/cv.typ", .data = typst_source });

    try stdout.writeAll("basic-resume/cv.typ generated. Running typst compile...\n");
    try stdout.flush();

    var child = std.process.spawn(global_io, .{
        .argv = &.{ "typst", "compile", "basic-resume/cv.typ" },
        .stdin = .ignore,
        .stdout = .ignore,
        .stderr = .ignore,
    }) catch |err| {
        try stdout.print("typst not available — run 'typst compile basic-resume/cv.typ' manually ({})\n", .{err});
        return;
    };
    const term = child.wait(global_io) catch |err| {
        try stdout.print("warning: failed to wait for typst: {}\n", .{err});
        return;
    };
    switch (term) {
        .exited => |code| {
            if (code == 0) {
                try stdout.writeAll("basic-resume/cv.typ compiled to PDF.\n");
            } else {
                try stdout.print("typst compile exited with code {d}.\n", .{code});
            }
        },
        else => {
            try stdout.writeAll("typst compile terminated abnormally.\n");
        },
    }
    try stdout.flush();
}

/// Returns `true` when the curated value is non-null and differs from the original.
fn changed(original: ?[]const u8, curated: ?[]const u8) bool {
    if (curated) |c| {
        if (original) |o| return !std.mem.eql(u8, o, c);
        return true;
    }
    return false;
}

/// Return the field value or "(not set)" for null.
fn displayField(field: ?[]const u8) []const u8 {
    return field orelse "(not set)";
}
