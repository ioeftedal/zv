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

/// The subset of LLM output that the application uses after curation.
pub const CuratedCv = struct {
    /// Professionally rewritten summary string.
    summary: ?[]const u8 = null,
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
    const summary = switch (root.object.get("summary") orelse return null) {
        .string => |s| s,
        else => return null,
    };

    return CuratedCv{
        .summary = try allocator.dupe(u8, summary),
    };
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

/// Perform an HTTP/1.1 POST to `/api/generate` and return the raw body.
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

    var read_buf: [65536]u8 = undefined;
    var stream_reader = stream.reader(io, &read_buf);
    var r = &stream_reader.interface;

    var content_length: ?usize = null;
    while (true) {
        const line = (try r.takeDelimiter('\n')) orelse break;
        if (line.len == 0) break;
        const header = if (line.len > 0 and line[line.len - 1] == '\r') line[0 .. line.len - 1] else line;
        if (contentLength(header)) |cl| {
            content_length = cl;
        }
    }

    var response = try std.ArrayList(u8).initCapacity(allocator, 0);
    defer response.deinit(allocator);

    if (content_length) |cl| {
        try r.appendExact(allocator, &response, cl);
    } else {
        try r.appendRemainingUnlimited(allocator, &response);
    }

    return try response.toOwnedSlice(allocator);
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
