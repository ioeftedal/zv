const std = @import("std");
const types = @import("../types.zig");
const writer = @import("../writer.zig");

const Profile = types.Profile;
const Education = types.Education;
const Experience = types.Experience;
const Project = types.Project;
const Certification = types.Certification;

fn baseInstruction(w: *writer.ListWriter) !void {
    try w.writeAll(
        \\You are a professional CV writer. Given the raw user data below for a single 
        \\entry, rewrite it into concise, impactful content suitable for a professional 
        \\resume. Only improve the language, wording, and professionalism within the 
        \\given entry — do not restructure, merge with other entries, or fabricate 
        \\information that wasn't already present. Add relevant keywords where 
        \\appropriate to strengthen the CV.
        \\
        \\Return ONLY a JSON object with no additional text or markdown formatting.
        \\
        \\
    );
}

pub fn buildProfilePrompt(p: Profile, allocator: std.mem.Allocator) ![]u8 {
    var buf = try std.ArrayList(u8).initCapacity(allocator, 0);
    var w = writer.ListWriter{ .list = &buf, .allocator = allocator };

    try baseInstruction(&w);
    try w.writeAll("PROFILE:\n");
    try w.print("Name: {s}\n", .{p.full_name});
    if (p.email) |v| try w.print("Email: {s}\n", .{v});
    if (p.phone) |v| try w.print("Phone: {s}\n", .{v});
    if (p.location) |v| try w.print("Location: {s}\n", .{v});
    if (p.title) |v| try w.print("Title: {s}\n", .{v});
    if (p.summary) |v| try w.print("Summary: {s}\n", .{v});
    try w.writeAll("\n");

    try w.writeAll(
        \\Return a JSON object with these fields:
        \\{
        \\  "title": "rewritten professional title or null",
        \\  "summary": "rewritten professional summary or null"
        \\}
    );

    return try buf.toOwnedSlice(allocator);
}

pub fn buildEducationPrompt(e: Education, allocator: std.mem.Allocator) ![]u8 {
    var buf = try std.ArrayList(u8).initCapacity(allocator, 0);
    var w = writer.ListWriter{ .list = &buf, .allocator = allocator };

    try baseInstruction(&w);
    try w.writeAll("EDUCATION ENTRY:\n");
    try w.print("Institution: {s}\n", .{e.institution});
    if (e.degree) |v| try w.print("Degree: {s}\n", .{v});
    if (e.field_of_study) |v| try w.print("Field: {s}\n", .{v});
    if (e.start_date) |v| try w.print("Start: {s}\n", .{v});
    if (e.end_date) |v| try w.print("End: {s}\n", .{v});
    if (e.highlights) |v| try w.print("Highlights: {s}\n", .{v});
    try w.writeAll("\n");

    try w.writeAll(
        \\Return a JSON object with these fields:
        \\{
        \\  "highlights": "rewritten highlights as a concise comma-separated string (elaborate on existing content, or null if none provided)"
        \\}
    );

    return try buf.toOwnedSlice(allocator);
}

pub fn buildExperiencePrompt(e: Experience, allocator: std.mem.Allocator) ![]u8 {
    var buf = try std.ArrayList(u8).initCapacity(allocator, 0);
    var w = writer.ListWriter{ .list = &buf, .allocator = allocator };

    try baseInstruction(&w);
    try w.writeAll("EXPERIENCE ENTRY:\n");
    try w.print("Company: {s}\n", .{e.company});
    if (e.position) |v| try w.print("Position: {s}\n", .{v});
    if (e.location) |v| try w.print("Location: {s}\n", .{v});
    if (e.start_date) |v| try w.print("Start: {s}\n", .{v});
    if (e.end_date) |v| try w.print("End: {s}\n", .{v});
    if (e.description) |v| try w.print("Description: {s}\n", .{v});
    if (e.highlights) |v| try w.print("Highlights: {s}\n", .{v});
    try w.writeAll("\n");

    try w.writeAll(
        \\Return a JSON object with these fields:
        \\{
        \\  "position": "rewritten position title or null",
        \\  "description": "rewritten description with professional language or null",
        \\  "highlights": "rewritten highlights as a concise comma-separated string or null"
        \\}
    );

    return try buf.toOwnedSlice(allocator);
}

pub fn buildProjectPrompt(p: Project, allocator: std.mem.Allocator) ![]u8 {
    var buf = try std.ArrayList(u8).initCapacity(allocator, 0);
    var w = writer.ListWriter{ .list = &buf, .allocator = allocator };

    try baseInstruction(&w);
    try w.writeAll("PROJECT ENTRY:\n");
    try w.print("Name: {s}\n", .{p.name});
    if (p.url) |v| try w.print("URL: {s}\n", .{v});
    if (p.description) |v| try w.print("Description: {s}\n", .{v});
    if (p.highlights) |v| try w.print("Highlights: {s}\n", .{v});
    try w.writeAll("\n");

    try w.writeAll(
        \\Return a JSON object with these fields:
        \\{
        \\  "description": "rewritten description with professional language or null",
        \\  "highlights": "rewritten highlights as a concise comma-separated string or null"
        \\}
    );

    return try buf.toOwnedSlice(allocator);
}

pub fn buildCertificationPrompt(c: Certification, allocator: std.mem.Allocator) ![]u8 {
    var buf = try std.ArrayList(u8).initCapacity(allocator, 0);
    var w = writer.ListWriter{ .list = &buf, .allocator = allocator };

    try baseInstruction(&w);
    try w.writeAll("CERTIFICATION ENTRY:\n");
    try w.print("Name: {s}\n", .{c.name});
    if (c.issuer) |v| try w.print("Issuer: {s}\n", .{v});
    if (c.date) |v| try w.print("Date: {s}\n", .{v});
    if (c.description) |v| try w.print("Description: {s}\n", .{v});
    try w.writeAll("\n");

    try w.writeAll(
        \\Return a JSON object with these fields:
        \\{
        \\  "description": "rewritten description with professional language or null"
        \\}
    );

    return try buf.toOwnedSlice(allocator);
}
