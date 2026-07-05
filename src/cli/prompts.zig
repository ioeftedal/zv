//! Interactive user prompts for data entry and editing.
//!
//! Each `prompt*` function collects field values from stdin and returns
//! a populated struct.  The `*ForEdit` variants pre-fill defaults from
//! the existing value so the user can press Enter to keep them.

const std = @import("std");
const Io = std.Io;
const types = @import("../types.zig");

const Profile = types.Profile;
const Education = types.Education;
const Experience = types.Experience;
const Project = types.Project;
const Skill = types.Skill;
const Certification = types.Certification;

/// Prompt to pick 0-3 (0 = keep original, 1-3 to accept that version).
/// Returns null on empty/EOF input, which the caller should treat as 0.
pub fn promptPickOption(stdout: *Io.Writer, stdin: *Io.Reader) !?u8 {
    try stdout.writeAll("  Choose 0-3 (0 = keep original): ");
    try stdout.flush();
    const line = (try stdin.takeDelimiter('\n')) orelse return null;
    const trimmed = std.mem.trim(u8, line, "\r");
    if (trimmed.len == 0) return null;
    const ch = trimmed[0];
    if (ch < '0' or ch > '3') return null;
    return ch - '0';
}

/// Read one line from stdin, trim trailing `\r`, and return an
/// owned copy.  Returns `null` on empty input or EOF.
fn readLine(allocator: std.mem.Allocator, stdin: *Io.Reader) !?[]const u8 {
    const line = (try stdin.takeDelimiter('\n')) orelse return null;
    const trimmed = std.mem.trim(u8, line, "\r");
    if (trimmed.len == 0) return null;
    return try allocator.dupe(u8, trimmed);
}

/// Prompt for a single field and return the user's input.
fn promptField(allocator: std.mem.Allocator, stdin: *Io.Reader, stdout: *Io.Writer, label: []const u8) !?[]const u8 {
    try stdout.print("{s}: ", .{label});
    try stdout.flush();
    return readLine(allocator, stdin);
}

pub fn promptProfile(allocator: std.mem.Allocator, stdin: *Io.Reader, stdout: *Io.Writer) !Profile {
    try stdout.writeAll("\n--- Profile ---\n");
    try stdout.flush();
    return Profile{
        .full_name = (try promptField(allocator, stdin, stdout, "Full name (required)")).?,
        .email = try promptField(allocator, stdin, stdout, "Email"),
        .phone = try promptField(allocator, stdin, stdout, "Phone"),
        .location = try promptField(allocator, stdin, stdout, "Location"),
        .title = try promptField(allocator, stdin, stdout, "Professional title"),
        .summary = try promptField(allocator, stdin, stdout, "Professional summary"),
    };
}

pub fn promptEducation(allocator: std.mem.Allocator, stdin: *Io.Reader, stdout: *Io.Writer) !Education {
    try stdout.writeAll("\n--- Education ---\n");
    try stdout.flush();
    return Education{
        .institution = (try promptField(allocator, stdin, stdout, "Institution (required)")).?,
        .degree = try promptField(allocator, stdin, stdout, "Degree"),
        .field_of_study = try promptField(allocator, stdin, stdout, "Field of study"),
        .start_date = try promptField(allocator, stdin, stdout, "Start date (e.g. Sep 2018)"),
        .end_date = try promptField(allocator, stdin, stdout, "End date (e.g. Jun 2022)"),
        .gpa = try promptField(allocator, stdin, stdout, "GPA"),
        .highlights = try promptField(allocator, stdin, stdout, "Highlights (comma-separated)"),
    };
}

pub fn promptExperience(allocator: std.mem.Allocator, stdin: *Io.Reader, stdout: *Io.Writer) !Experience {
    try stdout.writeAll("\n--- Experience ---\n");
    try stdout.flush();
    return Experience{
        .company = (try promptField(allocator, stdin, stdout, "Company (required)")).?,
        .position = try promptField(allocator, stdin, stdout, "Position"),
        .location = try promptField(allocator, stdin, stdout, "Location"),
        .start_date = try promptField(allocator, stdin, stdout, "Start date (e.g. Jan 2020)"),
        .end_date = try promptField(allocator, stdin, stdout, "End date (e.g. Present)"),
        .description = try promptField(allocator, stdin, stdout, "Description"),
        .highlights = try promptField(allocator, stdin, stdout, "Highlights (comma-separated)"),
    };
}

pub fn promptProject(allocator: std.mem.Allocator, stdin: *Io.Reader, stdout: *Io.Writer) !Project {
    try stdout.writeAll("\n--- Project ---\n");
    try stdout.flush();
    return Project{
        .name = (try promptField(allocator, stdin, stdout, "Project name (required)")).?,
        .description = try promptField(allocator, stdin, stdout, "Description"),
        .url = try promptField(allocator, stdin, stdout, "URL"),
        .technologies = try promptField(allocator, stdin, stdout, "Technologies (comma-separated)"),
        .start_date = try promptField(allocator, stdin, stdout, "Start date"),
        .end_date = try promptField(allocator, stdin, stdout, "End date"),
        .highlights = try promptField(allocator, stdin, stdout, "Highlights (comma-separated)"),
    };
}

pub fn promptSkill(allocator: std.mem.Allocator, stdin: *Io.Reader, stdout: *Io.Writer) !Skill {
    try stdout.writeAll("\n--- Skill ---\n");
    try stdout.flush();
    return Skill{
        .category = (try promptField(allocator, stdin, stdout, "Category (e.g. Programming)")).?,
        .skills = (try promptField(allocator, stdin, stdout, "Skills (comma-separated)")).?,
    };
}

pub fn promptCertification(allocator: std.mem.Allocator, stdin: *Io.Reader, stdout: *Io.Writer) !Certification {
    try stdout.writeAll("\n--- Certification ---\n");
    try stdout.flush();
    return Certification{
        .name = (try promptField(allocator, stdin, stdout, "Name (required)")).?,
        .issuer = try promptField(allocator, stdin, stdout, "Issuer"),
        .date = try promptField(allocator, stdin, stdout, "Date"),
        .url = try promptField(allocator, stdin, stdout, "URL"),
        .description = try promptField(allocator, stdin, stdout, "Description"),
    };
}

/// Prompt for a field showing the current value as a default in `[brackets]`.
/// An empty response preserves the current value.
fn promptFieldWithDefault(allocator: std.mem.Allocator, stdin: *Io.Reader, stdout: *Io.Writer, label: []const u8, current: ?[]const u8) !?[]const u8 {
    if (current) |cv| {
        try stdout.print("{s} [{s}]: ", .{ label, cv });
    } else {
        try stdout.print("{s}: ", .{label});
    }
    try stdout.flush();
    const line = (try stdin.takeDelimiter('\n')) orelse return current;
    const trimmed = std.mem.trim(u8, line, "\r");
    if (trimmed.len == 0) return current;
    return try allocator.dupe(u8, trimmed);
}

pub fn promptProfileForEdit(allocator: std.mem.Allocator, stdin: *Io.Reader, stdout: *Io.Writer, current: Profile) !Profile {
    try stdout.writeAll("\n--- Edit Profile ---\n");
    try stdout.flush();
    return Profile{
        .id = current.id,
        .full_name = (try promptFieldWithDefault(allocator, stdin, stdout, "Full name (required)", current.full_name)).?,
        .email = try promptFieldWithDefault(allocator, stdin, stdout, "Email", current.email),
        .phone = try promptFieldWithDefault(allocator, stdin, stdout, "Phone", current.phone),
        .location = try promptFieldWithDefault(allocator, stdin, stdout, "Location", current.location),
        .title = try promptFieldWithDefault(allocator, stdin, stdout, "Professional title", current.title),
        .summary = try promptFieldWithDefault(allocator, stdin, stdout, "Professional summary", current.summary),
    };
}

pub fn promptEducationForEdit(allocator: std.mem.Allocator, stdin: *Io.Reader, stdout: *Io.Writer, current: Education) !Education {
    try stdout.writeAll("\n--- Edit Education ---\n");
    try stdout.flush();
    return Education{
        .id = current.id,
        .institution = (try promptFieldWithDefault(allocator, stdin, stdout, "Institution (required)", current.institution)).?,
        .degree = try promptFieldWithDefault(allocator, stdin, stdout, "Degree", current.degree),
        .field_of_study = try promptFieldWithDefault(allocator, stdin, stdout, "Field of study", current.field_of_study),
        .start_date = try promptFieldWithDefault(allocator, stdin, stdout, "Start date (e.g. Sep 2018)", current.start_date),
        .end_date = try promptFieldWithDefault(allocator, stdin, stdout, "End date (e.g. Jun 2022)", current.end_date),
        .gpa = try promptFieldWithDefault(allocator, stdin, stdout, "GPA", current.gpa),
        .highlights = try promptFieldWithDefault(allocator, stdin, stdout, "Highlights (comma-separated)", current.highlights),
    };
}

pub fn promptExperienceForEdit(allocator: std.mem.Allocator, stdin: *Io.Reader, stdout: *Io.Writer, current: Experience) !Experience {
    try stdout.writeAll("\n--- Edit Experience ---\n");
    try stdout.flush();
    return Experience{
        .id = current.id,
        .company = (try promptFieldWithDefault(allocator, stdin, stdout, "Company (required)", current.company)).?,
        .position = try promptFieldWithDefault(allocator, stdin, stdout, "Position", current.position),
        .location = try promptFieldWithDefault(allocator, stdin, stdout, "Location", current.location),
        .start_date = try promptFieldWithDefault(allocator, stdin, stdout, "Start date (e.g. Jan 2020)", current.start_date),
        .end_date = try promptFieldWithDefault(allocator, stdin, stdout, "End date (e.g. Present)", current.end_date),
        .description = try promptFieldWithDefault(allocator, stdin, stdout, "Description", current.description),
        .highlights = try promptFieldWithDefault(allocator, stdin, stdout, "Highlights (comma-separated)", current.highlights),
    };
}

pub fn promptProjectForEdit(allocator: std.mem.Allocator, stdin: *Io.Reader, stdout: *Io.Writer, current: Project) !Project {
    try stdout.writeAll("\n--- Edit Project ---\n");
    try stdout.flush();
    return Project{
        .id = current.id,
        .name = (try promptFieldWithDefault(allocator, stdin, stdout, "Project name (required)", current.name)).?,
        .description = try promptFieldWithDefault(allocator, stdin, stdout, "Description", current.description),
        .url = try promptFieldWithDefault(allocator, stdin, stdout, "URL", current.url),
        .technologies = try promptFieldWithDefault(allocator, stdin, stdout, "Technologies (comma-separated)", current.technologies),
        .start_date = try promptFieldWithDefault(allocator, stdin, stdout, "Start date", current.start_date),
        .end_date = try promptFieldWithDefault(allocator, stdin, stdout, "End date", current.end_date),
        .highlights = try promptFieldWithDefault(allocator, stdin, stdout, "Highlights (comma-separated)", current.highlights),
    };
}

pub fn promptSkillForEdit(allocator: std.mem.Allocator, stdin: *Io.Reader, stdout: *Io.Writer, current: Skill) !Skill {
    try stdout.writeAll("\n--- Edit Skill ---\n");
    try stdout.flush();
    return Skill{
        .id = current.id,
        .category = (try promptFieldWithDefault(allocator, stdin, stdout, "Category (e.g. Programming)", current.category)).?,
        .skills = (try promptFieldWithDefault(allocator, stdin, stdout, "Skills (comma-separated)", current.skills)).?,
    };
}

pub fn promptCertificationForEdit(allocator: std.mem.Allocator, stdin: *Io.Reader, stdout: *Io.Writer, current: Certification) !Certification {
    try stdout.writeAll("\n--- Edit Certification ---\n");
    try stdout.flush();
    return Certification{
        .id = current.id,
        .name = (try promptFieldWithDefault(allocator, stdin, stdout, "Name (required)", current.name)).?,
        .issuer = try promptFieldWithDefault(allocator, stdin, stdout, "Issuer", current.issuer),
        .date = try promptFieldWithDefault(allocator, stdin, stdout, "Date", current.date),
        .url = try promptFieldWithDefault(allocator, stdin, stdout, "URL", current.url),
        .description = try promptFieldWithDefault(allocator, stdin, stdout, "Description", current.description),
    };
}
