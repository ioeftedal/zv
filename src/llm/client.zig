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

pub fn isOllamaRunning(io: Io) bool {
    const address = Io.net.IpAddress.parseIp4(ollama_host, ollama_port) catch return false;
    const stream = address.connect(io, .{ .mode = .stream }) catch return false;
    stream.close(io);
    return true;
}

pub fn curateCv(
    io: Io,
    allocator: std.mem.Allocator,
    profile: ?Profile,
    education: []const Education,
    experience: []const Experience,
    projects: []const Project,
    skills: []const Skill,
    certifications: []const Certification,
) !?[]u8 {
    const prompt = try templates.buildPrompt(
        profile, education, experience, projects, skills, certifications, allocator,
    );
    defer allocator.free(prompt);

    const json_body = try std.fmt.allocPrint(allocator, "{f}", .{std.json.fmt(.{
        .model = model_name,
        .prompt = prompt,
        .stream = false,
    }, .{})});
    defer allocator.free(json_body);

    const raw_response = try sendRequest(io, allocator, json_body);

    const response_text = try extractResponse(raw_response, allocator);
    return response_text;
}

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

    var read_buf: [65536]u8 = undefined;
    var stream_reader = stream.reader(io, &read_buf);
    var r = &stream_reader.interface;

    var content_length: ?usize = null;
    while (true) {
        const line = (try r.takeDelimiter('\n')) orelse break;
        if (line.len == 0) break;
        if (std.mem.indexOf(u8, line, "content-length:") != null or
            std.mem.indexOf(u8, line, "Content-Length:") != null)
        {
            const colon_idx = std.mem.indexOf(u8, line, ":") orelse continue;
            const num_str = std.mem.trim(u8, line[colon_idx + 1 ..], " \t\r");
            content_length = std.fmt.parseInt(usize, num_str, 10) catch null;
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
