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

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const io = init.io;

    var database = try db.init("cv.db");
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
            '1' => try handleAdd(&database, stdin, stdout, arena),
            '2' => try handleList(&database, stdin, stdout, arena),
            '3' => try handleEdit(&database, stdin, stdout, arena),
            '4' => try handleDelete(&database, stdin, stdout, arena),
            '5' => try handleGenerate(&database, io, stdout, arena, ollama_ok),
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

fn readByte(stdin: *Io.Reader) u8 {
    const line = (stdin.takeDelimiter('\n') catch return '6') orelse return '6';
    if (line.len == 0) return '6';
    return line[0];
}

fn readChoice(stdin: *Io.Reader) u8 {
    const line = (stdin.takeDelimiter('\n') catch return '7') orelse return '7';
    if (line.len == 0) return '7';
    return line[0];
}

fn handleAdd(database: *sqlite.Db, stdin: *Io.Reader, stdout: *Io.Writer, allocator: std.mem.Allocator) !void {
    try menu.showCategoryMenu(stdout);
    try stdout.flush();
    const cat = readChoice(stdin);

    switch (cat) {
        '1' => {
            const p = try prompts.promptProfile(allocator, stdin, stdout);
            try models.insertProfile(database, p);
            try stdout.writeAll("Profile saved.\n");
        },
        '2' => {
            const e = try prompts.promptEducation(allocator, stdin, stdout);
            try models.insertEducation(database, e);
            try stdout.writeAll("Education saved.\n");
        },
        '3' => {
            const e = try prompts.promptExperience(allocator, stdin, stdout);
            try models.insertExperience(database, e);
            try stdout.writeAll("Experience saved.\n");
        },
        '4' => {
            const p = try prompts.promptProject(allocator, stdin, stdout);
            try models.insertProject(database, p);
            try stdout.writeAll("Project saved.\n");
        },
        '5' => {
            const s = try prompts.promptSkill(allocator, stdin, stdout);
            try models.insertSkill(database, s);
            try stdout.writeAll("Skill saved.\n");
        },
        '6' => {
            const c = try prompts.promptCertification(allocator, stdin, stdout);
            try models.insertCertification(database, c);
            try stdout.writeAll("Certification saved.\n");
        },
        else => {},
    }
    try stdout.flush();
}

fn handleList(database: *sqlite.Db, stdin: *Io.Reader, stdout: *Io.Writer, allocator: std.mem.Allocator) !void {
    try menu.showCategoryMenu(stdout);
    try stdout.flush();
    const cat = readChoice(stdin);
    _ = allocator;

    switch (cat) {
        '1' => {
            if (try models.getProfile(database)) |p| {
                try stdout.print("Profile: {s}\n", .{p.full_name});
            } else {
                try stdout.writeAll("No profile.\n");
            }
        },
        '2' => {
            const items = try models.getAllEducation(database);
            for (items) |e| {
                try stdout.print("  {s} – {s}\n", .{ e.institution, e.degree orelse "" });
            }
        },
        '3' => {
            const items = try models.getAllExperience(database);
            for (items) |e| {
                try stdout.print("  {s} – {s}\n", .{ e.company, e.position orelse "" });
            }
        },
        '4' => {
            const items = try models.getAllProjects(database);
            for (items) |p| {
                try stdout.print("  {s}\n", .{p.name});
            }
        },
        '5' => {
            const items = try models.getAllSkills(database);
            for (items) |s| {
                try stdout.print("  {s}: {s}\n", .{ s.category, s.skills });
            }
        },
        '6' => {
            const items = try models.getAllCertifications(database);
            for (items) |c| {
                try stdout.print("  {s}\n", .{c.name});
            }
        },
        else => {},
    }
    try stdout.flush();
}

fn readIndex(stdin: *Io.Reader) ?usize {
    const line = (stdin.takeDelimiter('\n') catch return null) orelse return null;
    const trimmed = std.mem.trim(u8, line, "\r");
    if (trimmed.len == 0) return null;
    return std.fmt.parseInt(usize, trimmed, 10) catch null;
}

fn handleEdit(database: *sqlite.Db, stdin: *Io.Reader, stdout: *Io.Writer, allocator: std.mem.Allocator) !void {
    try menu.showCategoryMenu(stdout);
    try stdout.flush();
    const cat = readChoice(stdin);

    switch (cat) {
        '1' => {
            if (try models.getProfile(database)) |p| {
                const updated = try prompts.promptProfileForEdit(allocator, stdin, stdout, p);
                try models.updateProfile(database, updated);
                try stdout.writeAll("Profile updated.\n");
            } else {
                try stdout.writeAll("No profile. Add one first.\n");
            }
        },
        '2' => {
            const items = try models.getAllEducation(database);
            if (items.len == 0) return try stdout.writeAll("No education entries.\n");
            for (items, 0..) |e, i| {
                try stdout.print("{d}) {s} – {s}\n", .{ i + 1, e.institution, e.degree orelse "" });
            }
            try stdout.writeAll("Enter number to edit (0 to cancel): ");
            try stdout.flush();
            const idx = (readIndex(stdin) orelse 0);
            if (idx == 0 or idx > items.len) return;
            const updated = try prompts.promptEducationForEdit(allocator, stdin, stdout, items[idx - 1]);
            try models.updateEducation(database, updated);
            try stdout.writeAll("Education entry updated.\n");
        },
        '3' => {
            const items = try models.getAllExperience(database);
            if (items.len == 0) return try stdout.writeAll("No experience entries.\n");
            for (items, 0..) |e, i| {
                try stdout.print("{d}) {s} – {s}\n", .{ i + 1, e.company, e.position orelse "" });
            }
            try stdout.writeAll("Enter number to edit (0 to cancel): ");
            try stdout.flush();
            const idx = (readIndex(stdin) orelse 0);
            if (idx == 0 or idx > items.len) return;
            const updated = try prompts.promptExperienceForEdit(allocator, stdin, stdout, items[idx - 1]);
            try models.updateExperience(database, updated);
            try stdout.writeAll("Experience entry updated.\n");
        },
        '4' => {
            const items = try models.getAllProjects(database);
            if (items.len == 0) return try stdout.writeAll("No project entries.\n");
            for (items, 0..) |p, i| {
                try stdout.print("{d}) {s}\n", .{ i + 1, p.name });
            }
            try stdout.writeAll("Enter number to edit (0 to cancel): ");
            try stdout.flush();
            const idx = (readIndex(stdin) orelse 0);
            if (idx == 0 or idx > items.len) return;
            const updated = try prompts.promptProjectForEdit(allocator, stdin, stdout, items[idx - 1]);
            try models.updateProject(database, updated);
            try stdout.writeAll("Project entry updated.\n");
        },
        '5' => {
            const items = try models.getAllSkills(database);
            if (items.len == 0) return try stdout.writeAll("No skill entries.\n");
            for (items, 0..) |s, i| {
                try stdout.print("{d}) {s}: {s}\n", .{ i + 1, s.category, s.skills });
            }
            try stdout.writeAll("Enter number to edit (0 to cancel): ");
            try stdout.flush();
            const idx = (readIndex(stdin) orelse 0);
            if (idx == 0 or idx > items.len) return;
            const updated = try prompts.promptSkillForEdit(allocator, stdin, stdout, items[idx - 1]);
            try models.updateSkill(database, updated);
            try stdout.writeAll("Skill entry updated.\n");
        },
        '6' => {
            const items = try models.getAllCertifications(database);
            if (items.len == 0) return try stdout.writeAll("No certification entries.\n");
            for (items, 0..) |c, i| {
                try stdout.print("{d}) {s}\n", .{ i + 1, c.name });
            }
            try stdout.writeAll("Enter number to edit (0 to cancel): ");
            try stdout.flush();
            const idx = (readIndex(stdin) orelse 0);
            if (idx == 0 or idx > items.len) return;
            const updated = try prompts.promptCertificationForEdit(allocator, stdin, stdout, items[idx - 1]);
            try models.updateCertification(database, updated);
            try stdout.writeAll("Certification entry updated.\n");
        },
        else => {},
    }
    try stdout.flush();
}

fn handleDelete(database: *sqlite.Db, stdin: *Io.Reader, stdout: *Io.Writer, allocator: std.mem.Allocator) !void {
    _ = allocator;
    try menu.showCategoryMenu(stdout);
    try stdout.flush();
    const cat = readChoice(stdin);

    switch (cat) {
        '1' => try stdout.writeAll("Cannot delete profile.\n"),
        '2' => {
            const items = try models.getAllEducation(database);
            if (items.len == 0) return try stdout.writeAll("No education entries.\n");
            for (items, 0..) |e, i| {
                try stdout.print("{d}) {s} – {s}\n", .{ i + 1, e.institution, e.degree orelse "" });
            }
            try stdout.writeAll("Enter number to delete (0 to cancel): ");
            try stdout.flush();
            const idx = (readIndex(stdin) orelse 0);
            if (idx == 0 or idx > items.len) return;
            try stdout.print("Are you sure you want to delete \"{s}\"? (y/N): ", .{items[idx - 1].institution});
            try stdout.flush();
            const confirm = readByte(stdin);
            if (confirm == 'y' or confirm == 'Y') {
                try models.deleteEducation(database, items[idx - 1].id.?);
                try stdout.writeAll("Education entry deleted.\n");
            }
        },
        '3' => {
            const items = try models.getAllExperience(database);
            if (items.len == 0) return try stdout.writeAll("No experience entries.\n");
            for (items, 0..) |e, i| {
                try stdout.print("{d}) {s} – {s}\n", .{ i + 1, e.company, e.position orelse "" });
            }
            try stdout.writeAll("Enter number to delete (0 to cancel): ");
            try stdout.flush();
            const idx = (readIndex(stdin) orelse 0);
            if (idx == 0 or idx > items.len) return;
            try stdout.print("Are you sure you want to delete \"{s}\"? (y/N): ", .{items[idx - 1].company});
            try stdout.flush();
            const confirm = readByte(stdin);
            if (confirm == 'y' or confirm == 'Y') {
                try models.deleteExperience(database, items[idx - 1].id.?);
                try stdout.writeAll("Experience entry deleted.\n");
            }
        },
        '4' => {
            const items = try models.getAllProjects(database);
            if (items.len == 0) return try stdout.writeAll("No project entries.\n");
            for (items, 0..) |p, i| {
                try stdout.print("{d}) {s}\n", .{ i + 1, p.name });
            }
            try stdout.writeAll("Enter number to delete (0 to cancel): ");
            try stdout.flush();
            const idx = (readIndex(stdin) orelse 0);
            if (idx == 0 or idx > items.len) return;
            try stdout.print("Are you sure you want to delete \"{s}\"? (y/N): ", .{items[idx - 1].name});
            try stdout.flush();
            const confirm = readByte(stdin);
            if (confirm == 'y' or confirm == 'Y') {
                try models.deleteProject(database, items[idx - 1].id.?);
                try stdout.writeAll("Project entry deleted.\n");
            }
        },
        '5' => {
            const items = try models.getAllSkills(database);
            if (items.len == 0) return try stdout.writeAll("No skill entries.\n");
            for (items, 0..) |s, i| {
                try stdout.print("{d}) {s}: {s}\n", .{ i + 1, s.category, s.skills });
            }
            try stdout.writeAll("Enter number to delete (0 to cancel): ");
            try stdout.flush();
            const idx = (readIndex(stdin) orelse 0);
            if (idx == 0 or idx > items.len) return;
            try stdout.print("Are you sure you want to delete \"{s}\"? (y/N): ", .{items[idx - 1].category});
            try stdout.flush();
            const confirm = readByte(stdin);
            if (confirm == 'y' or confirm == 'Y') {
                try models.deleteSkill(database, items[idx - 1].id.?);
                try stdout.writeAll("Skill entry deleted.\n");
            }
        },
        '6' => {
            const items = try models.getAllCertifications(database);
            if (items.len == 0) return try stdout.writeAll("No certification entries.\n");
            for (items, 0..) |c, i| {
                try stdout.print("{d}) {s}\n", .{ i + 1, c.name });
            }
            try stdout.writeAll("Enter number to delete (0 to cancel): ");
            try stdout.flush();
            const idx = (readIndex(stdin) orelse 0);
            if (idx == 0 or idx > items.len) return;
            try stdout.print("Are you sure you want to delete \"{s}\"? (y/N): ", .{items[idx - 1].name});
            try stdout.flush();
            const confirm = readByte(stdin);
            if (confirm == 'y' or confirm == 'Y') {
                try models.deleteCertification(database, items[idx - 1].id.?);
                try stdout.writeAll("Certification entry deleted.\n");
            }
        },
        else => {},
    }
    try stdout.flush();
}

fn handleGenerate(database: *sqlite.Db, io: Io, stdout: *Io.Writer, allocator: std.mem.Allocator, ollama_ok: bool) !void {
    try stdout.writeAll("Generating CV...\n");
    try stdout.flush();

    const profile = try models.getProfile(database);
    const education = try models.getAllEducation(database);
    const experience = try models.getAllExperience(database);
    const projects = try models.getAllProjects(database);
    const skills = try models.getAllSkills(database);
    const certifications = try models.getAllCertifications(database);

    if (ollama_ok) {
        const _curated = try llm.curateCv(
            io, allocator, profile, education, experience, projects, skills, certifications,
        );
        allocator.free(_curated.?);
    }

    const typst_source = try render.generateTypst(
        profile, education, experience, projects, skills, certifications, allocator,
    );
    defer allocator.free(typst_source);

    const cwd = std.Io.Dir.cwd();
    try cwd.writeFile(io, .{ .sub_path = "basic-resume/cv.typ", .data = typst_source });

    try stdout.writeAll("basic-resume/cv.typ generated. Running typst compile...\n");
    try stdout.flush();

    var child = std.process.spawn(io, .{
        .argv = &.{ "typst", "compile", "basic-resume/cv.typ" },
        .stdin = .ignore,
        .stdout = .ignore,
        .stderr = .ignore,
    }) catch |err| {
        try stdout.print("typst not available — run 'typst compile basic-resume/cv.typ' manually ({})\n", .{err});
        return;
    };
    const term = child.wait(io) catch |err| {
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
