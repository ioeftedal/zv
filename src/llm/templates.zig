//! LLM prompt construction from user data.
//!
//! `buildPrompt` serialises every CV section into a plain-text prompt
//! that instructs an LLM (via Ollama) to rewrite the content into
//! polished, resume-ready JSON.

const std = @import("std");
const types = @import("../types.zig");
const writer = @import("../writer.zig");

const Profile = types.Profile;
const Education = types.Education;
const Experience = types.Experience;
const Project = types.Project;
const Skill = types.Skill;
const Certification = types.Certification;

/// Build a prompt that instructs the LLM to rewrite raw CV data into
/// concise, impactful resume content.
///
/// The returned slice is owned by the caller.
pub fn buildPrompt(
    profile: ?Profile,
    education: []const Education,
    experience: []const Experience,
    projects: []const Project,
    skills: []const Skill,
    certifications: []const Certification,
    allocator: std.mem.Allocator,
) ![]u8 {
    var buf = try std.ArrayList(u8).initCapacity(allocator, 0);
    var w = writer.ListWriter{ .list = &buf, .allocator = allocator };

    try w.writeAll(
        \\You are a professional CV writer. Given the raw user data below, rewrite it into 
        \\concise, impactful content suitable for a professional resume. Return ONLY a JSON 
        \\object with no additional text or markdown formatting.
        \\
        \\
    );

    if (profile) |p| {
        try w.print("PROFILE:\nName: {s}\n", .{p.full_name});
        if (p.email) |v| try w.print("Email: {s}\n", .{v});
        if (p.phone) |v| try w.print("Phone: {s}\n", .{v});
        if (p.location) |v| try w.print("Location: {s}\n", .{v});
        if (p.title) |v| try w.print("Title: {s}\n", .{v});
        if (p.summary) |v| try w.print("Summary: {s}\n", .{v});
        try w.writeAll("\n");
    }

    if (education.len > 0) {
        try w.writeAll("EDUCATION:\n");
        for (education) |e| {
            try w.print("- {s}", .{e.institution});
            if (e.degree) |v| try w.print(", {s}", .{v});
            if (e.field_of_study) |v| try w.print(", {s}", .{v});
            if (e.start_date) |v| try w.print(" ({s}", .{v});
            if (e.end_date) |v| try w.print(" - {s}", .{v});
            if (e.start_date != null or e.end_date != null) try w.writeAll(")");
            try w.writeAll("\n");
        }
        try w.writeAll("\n");
    }

    if (experience.len > 0) {
        try w.writeAll("EXPERIENCE:\n");
        for (experience) |e| {
            try w.print("- {s} at {s}", .{ e.position orelse "Position", e.company });
            if (e.location) |v| try w.print(", {s}", .{v});
            if (e.start_date) |v| try w.print(" ({s}", .{v});
            if (e.end_date) |v| try w.print(" - {s}", .{v});
            if (e.start_date != null or e.end_date != null) try w.writeAll(")");
            try w.writeAll("\n");
            if (e.description) |v| try w.print("  {s}\n", .{v});
        }
        try w.writeAll("\n");
    }

    if (projects.len > 0) {
        try w.writeAll("PROJECTS:\n");
        for (projects) |p| {
            try w.print("- {s}", .{p.name});
            if (p.url) |v| try w.print(" ({s})", .{v});
            try w.writeAll("\n");
            if (p.description) |v| try w.print("  {s}\n", .{v});
        }
        try w.writeAll("\n");
    }

    if (skills.len > 0) {
        try w.writeAll("SKILLS:\n");
        for (skills) |s| {
            try w.print("- {s}: {s}\n", .{ s.category, s.skills });
        }
        try w.writeAll("\n");
    }

    if (certifications.len > 0) {
        try w.writeAll("CERTIFICATIONS:\n");
        for (certifications) |c| {
            try w.print("- {s}", .{c.name});
            if (c.issuer) |v| try w.print(", {s}", .{v});
            if (c.date) |v| try w.print(" ({s})", .{v});
            try w.writeAll("\n");
        }
        try w.writeAll("\n");
    }

    try w.writeAll(
        \\Return a JSON object with the following structure (use null for missing fields).
        \\Only include fields that can be rewritten — preserve the array order and count.
        \\{
        \\  "profile": {
        \\    "title": "rewritten professional title or null",
        \\    "summary": "rewritten professional summary or null"
        \\  },
        \\  "education": [
        \\    {"highlights": "rewritten highlights as comma-separated string or null"}
        \\  ],
        \\  "experience": [
        \\    {"position": "rewritten position or null", "description": "rewritten description or null", "highlights": "rewritten highlights as comma-separated string or null"}
        \\  ],
        \\  "projects": [
        \\    {"description": "rewritten description or null", "highlights": "rewritten highlights as comma-separated string or null"}
        \\  ],
        \\  "certifications": [
        \\    {"description": "rewritten description or null"}
        \\  ]
        \\}
    );

    return try buf.toOwnedSlice(allocator);
}
