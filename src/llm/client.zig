//! HTTP client for Ollama's `/api/generate` endpoint.
//!
//! Connects to a local Ollama instance via raw TCP and sends a
//! non-streaming generate request.  The LLM response is parsed and
//! the curated summary is returned as a `CuratedCv`.

const std = @import("std");
const Io = std.Io;
const types = @import("../types.zig");
const templates = @import("templates.zig");

const Profile = types.Profile;
const Education = types.Education;
const Experience = types.Experience;
const Project = types.Project;
const Skill = types.Skill;
const Certification = types.Certification;

const model_name = "llama3.2";
const ollama_host = "127.0.0.1";
const ollama_port = 11434;

/// Rewritable fields for a profile.
pub const CuratedProfile = struct {
    title: ?[]const u8 = null,
    summary: ?[]const u8 = null,
};

/// Rewritable fields for an education entry.
pub const CuratedEducation = struct {
    highlights: ?[]const u8 = null,
};

/// Rewritable fields for an experience entry.
pub const CuratedExperience = struct {
    position: ?[]const u8 = null,
    description: ?[]const u8 = null,
    highlights: ?[]const u8 = null,
};

/// Rewritable fields for a project entry.
pub const CuratedProject = struct {
    description: ?[]const u8 = null,
    highlights: ?[]const u8 = null,
};

/// Rewritable fields for a certification entry.
pub const CuratedCertification = struct {
    description: ?[]const u8 = null,
};

/// The full set of LLM output that the application uses after curation.
pub const CuratedCv = struct {
    profile: ?CuratedProfile = null,
    education: []const CuratedEducation = &.{},
    experience: []const CuratedExperience = &.{},
    projects: []const CuratedProject = &.{},
    certifications: []const CuratedCertification = &.{},
};

/// Returns `true` if a TCP connection to the local Ollama server can
/// be established.
pub fn isOllamaRunning(io: Io) bool {
    const address = Io.net.IpAddress.parseIp4(ollama_host, ollama_port) catch return false;
    const stream = address.connect(io, .{ .mode = .stream }) catch return false;
    stream.close(io);
    return true;
}

/// Send all CV data to Ollama for AI-powered rewrite.
///
/// Builds a prompt, sends it to `/api/generate`, and extracts the
/// curated `summary` from the JSON response.  Returns `null` if the
/// LLM output cannot be parsed (callers handle the fallback).
pub fn curateCv(
    io: Io,
    allocator: std.mem.Allocator,
    profile: ?Profile,
    education: []const Education,
    experience: []const Experience,
    projects: []const Project,
    skills: []const Skill,
    certifications: []const Certification,
) !?CuratedCv {
    const prompt = try templates.buildPrompt(
        profile,
        education,
        experience,
        projects,
        skills,
        certifications,
        allocator,
    );
    defer allocator.free(prompt);

    const json_body = try std.fmt.allocPrint(allocator, "{f}", .{std.json.fmt(.{
        .model = model_name,
        .prompt = prompt,
        .stream = false,
    }, .{})});
    defer allocator.free(json_body);

    const raw_response = try sendRequest(io, allocator, json_body);

    const response_text = try extractResponse(raw_response, allocator) orelse return null;
    defer allocator.free(response_text);

    return try parseCuratedResponse(response_text, allocator);
}

/// Parse the LLM's JSON output into a `CuratedCv`.
fn parseCuratedResponse(raw: []const u8, allocator: std.mem.Allocator) !?CuratedCv {
    const trimmed = std.mem.trim(u8, raw, " \t\r\n");
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, trimmed, .{});
    defer parsed.deinit();

    const root = parsed.value;

    const profile_val = root.object.get("profile");
    const profile: ?CuratedProfile = if (profile_val) |pv| blk: {
        break :blk CuratedProfile{
            .title = try extractString(pv, "title", allocator),
            .summary = try extractString(pv, "summary", allocator),
        };
    } else null;

    const education = try extractEducationArray(allocator, root);
    const experience = try extractExperienceArray(allocator, root);
    const projects = try extractProjectArray(allocator, root);
    const certifications = try extractCertificationArray(allocator, root);

    return CuratedCv{
        .profile = profile,
        .education = education,
        .experience = experience,
        .projects = projects,
        .certifications = certifications,
    };
}

/// Extract a nullable string field from a JSON object value.
fn extractString(value: std.json.Value, field: []const u8, allocator: std.mem.Allocator) !?[]const u8 {
    const val = value.object.get(field) orelse return null;
    return switch (val) {
        .string => |s| try allocator.dupe(u8, s),
        else => null,
    };
}

/// Extract highlights from a JSON value, handling both string and array-of-strings.
fn extractHighlights(value: std.json.Value, allocator: std.mem.Allocator) !?[]const u8 {
    const val = value.object.get("highlights") orelse return null;
    return switch (val) {
        .string => |s| try allocator.dupe(u8, s),
        .array => |arr| blk: {
            var buf = try std.ArrayList(u8).initCapacity(allocator, 0);
            for (arr.items, 0..) |item, i| {
                if (i > 0) try buf.appendSlice(allocator, ", ");
                const s = switch (item) {
                    .string => |s| s,
                    else => continue,
                };
                try buf.appendSlice(allocator, s);
            }
            break :blk try buf.toOwnedSlice(allocator);
        },
        else => null,
    };
}

fn extractObjectArray(root: std.json.Value, field: []const u8) []std.json.Value {
    const val = root.object.get(field) orelse return &.{};
    return switch (val) {
        .array => |arr| arr.items,
        else => &.{},
    };
}

fn extractEducationArray(allocator: std.mem.Allocator, root: std.json.Value) ![]const CuratedEducation {
    const items = extractObjectArray(root, "education");
    const result = try allocator.alloc(CuratedEducation, items.len);
    for (items, 0..) |item, i| {
        result[i] = .{
            .highlights = try extractHighlights(item, allocator),
        };
    }
    return result;
}

fn extractExperienceArray(allocator: std.mem.Allocator, root: std.json.Value) ![]const CuratedExperience {
    const items = extractObjectArray(root, "experience");
    const result = try allocator.alloc(CuratedExperience, items.len);
    for (items, 0..) |item, i| {
        result[i] = .{
            .position = try extractString(item, "position", allocator),
            .description = try extractString(item, "description", allocator),
            .highlights = try extractHighlights(item, allocator),
        };
    }
    return result;
}

fn extractProjectArray(allocator: std.mem.Allocator, root: std.json.Value) ![]const CuratedProject {
    const items = extractObjectArray(root, "projects");
    const result = try allocator.alloc(CuratedProject, items.len);
    for (items, 0..) |item, i| {
        result[i] = .{
            .description = try extractString(item, "description", allocator),
            .highlights = try extractHighlights(item, allocator),
        };
    }
    return result;
}

fn extractCertificationArray(allocator: std.mem.Allocator, root: std.json.Value) ![]const CuratedCertification {
    const items = extractObjectArray(root, "certifications");
    const result = try allocator.alloc(CuratedCertification, items.len);
    for (items, 0..) |item, i| {
        result[i] = .{
            .description = try extractString(item, "description", allocator),
        };
    }
    return result;
}

/// Extract the `"response"` field from Ollama's JSON envelope.
fn extractResponse(raw: []const u8, allocator: std.mem.Allocator) !?[]u8 {
    const trimmed = std.mem.trim(u8, raw, " \t\r\n");
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, trimmed, .{});
    defer parsed.deinit();

    const root = parsed.value;
    const response_val = root.object.get("response") orelse return null;
    const text = switch (response_val) {
        .string => |s| s,
        else => return null,
    };
    return try allocator.dupe(u8, text);
}

fn sendRequest(io: Io, allocator: std.mem.Allocator, body: []const u8) ![]u8 {
    const address = try Io.net.IpAddress.parseIp4(ollama_host, ollama_port);
    const stream = try address.connect(io, .{ .mode = .stream });
    defer stream.close(io);

    var write_buf: [8192]u8 = undefined;
    var stream_writer = stream.writer(io, &write_buf);
    var w = &stream_writer.interface;
    try w.print("POST /api/generate HTTP/1.1\r\n", .{});
    try w.print("Host: 127.0.0.1:{d}\r\n", .{ollama_port});
    try w.print("Content-Type: application/json\r\n", .{});
    try w.print("Content-Length: {d}\r\n", .{body.len});
    try w.print("\r\n", .{});
    try w.writeAll(body);
    try w.flush();

    var raw = try std.ArrayList(u8).initCapacity(allocator, 4096);
    defer raw.deinit(allocator);

    var buf: [65536]u8 = undefined;
    var iov: [1][]u8 = .{buf[0..]};

    while (std.mem.indexOf(u8, raw.items, "\r\n\r\n") == null) {
        const n = try stream.read(io, &iov);
        if (n == 0) return error.ConnectionReset;
        try raw.appendSlice(allocator, buf[0..n]);
    }

    const response = raw.items;
    const first_nl = std.mem.indexOfScalar(u8, response, '\n') orelse return error.ConnectionReset;
    const line = response[0..first_nl];
    {
        var it = std.mem.splitScalar(u8, line, ' ');
        _ = it.first();
        const status_str = it.next() orelse return error.ConnectionReset;
        const status = std.fmt.parseInt(u16, status_str, 10) catch return error.ConnectionReset;
        if (status < 200 or status >= 300) {
            std.log.err("ollama returned status {d}", .{status});
            return error.OllamaError;
        }
    }

    const hdr_end = (std.mem.indexOf(u8, response, "\r\n\r\n") orelse return error.OllamaProtocol) + 4;
    const header_block = response[0..hdr_end];
    const raw_body = response[hdr_end..];

    if (std.mem.indexOf(u8, header_block, "chunked") != null) {
        var accum = try std.ArrayList(u8).initCapacity(allocator, raw_body.len);
        defer accum.deinit(allocator);
        try accum.appendSlice(allocator, raw_body);

        var out = try std.ArrayList(u8).initCapacity(allocator, accum.items.len);
        defer out.deinit(allocator);

        while (true) {
            // Find next \n in unparsed portion for chunk size
            const nl = std.mem.indexOfScalar(u8, accum.items, '\n') orelse blk: {
                const n = try stream.read(io, &iov);
                if (n == 0) return error.ConnectionReset;
                try accum.appendSlice(allocator, buf[0..n]);
                break :blk std.mem.indexOfScalar(u8, accum.items, '\n') orelse return error.OllamaProtocol;
            };
            const chunk_line = accum.items[0..nl];
            const trimmed = std.mem.trim(u8, chunk_line, "\r");
            const chunk_size = std.fmt.parseInt(usize, trimmed, 16) catch return error.OllamaProtocol;
            const total_needed = nl + 1 + chunk_size + 2;
            while (accum.items.len < total_needed) {
                const n = try stream.read(io, &iov);
                if (n == 0) return error.ConnectionReset;
                try accum.appendSlice(allocator, buf[0..n]);
            }
            if (chunk_size == 0) {
                return try out.toOwnedSlice(allocator);
            }
            const chunk_start = nl + 1;
            try out.appendSlice(allocator, accum.items[chunk_start .. chunk_start + chunk_size]);
            // Discard processed data (size line + chunk data + \r\n)
            const consumed = chunk_start + chunk_size + 2;
            const remaining = try allocator.dupe(u8, accum.items[consumed..]);
            defer allocator.free(remaining);
            accum.clearRetainingCapacity();
            try accum.appendSlice(allocator, remaining);
        }
    } else {
        const cl = content_length_blk: {
            var hdr_it = std.mem.splitSequence(u8, header_block, "\r\n");
            var content_length: ?usize = null;
            while (hdr_it.next()) |hdr| {
                if (contentLength(hdr)) |cl| {
                    content_length = cl;
                }
            }
            break :content_length_blk content_length orelse {
                std.log.err("ollama response missing Content-Length header", .{});
                return error.OllamaProtocol;
            };
        };
        var out = try std.ArrayList(u8).initCapacity(allocator, raw_body.len);
        defer out.deinit(allocator);
        try out.appendSlice(allocator, raw_body);
        if (raw_body.len < cl) {
            try out.resize(allocator, cl);
            var offset: usize = raw_body.len;
            var iov2: [1][]u8 = undefined;
            while (offset < cl) {
                iov2[0] = out.items[offset..];
                const m = try stream.read(io, &iov2);
                if (m == 0) return error.ConnectionReset;
                offset += m;
            }
        }
        return try out.toOwnedSlice(allocator);
    }
    return error.OllamaProtocol;
}

/// Parse the `Content-Length` value from an HTTP response header.
fn contentLength(header: []const u8) ?usize {
    const label = "content-length:";
    if (header.len < label.len) return null;
    const prefix = header[0..label.len];
    if (!std.ascii.eqlIgnoreCase(prefix, label)) return null;

    const value_start = label.len;
    const trimmed = std.mem.trim(u8, header[value_start..], " \t\r");
    return std.fmt.parseInt(usize, trimmed, 10) catch null;
}
