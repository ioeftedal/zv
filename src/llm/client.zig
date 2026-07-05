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

pub const CuratedProfile = struct {
    title: ?[]const u8 = null,
    summary: ?[]const u8 = null,
};

pub const CuratedEducation = struct {
    highlights: ?[]const u8 = null,
};

pub const CuratedExperience = struct {
    position: ?[]const u8 = null,
    description: ?[]const u8 = null,
    highlights: ?[]const u8 = null,
};

pub const CuratedProject = struct {
    description: ?[]const u8 = null,
    highlights: ?[]const u8 = null,
};

pub const CuratedCertification = struct {
    description: ?[]const u8 = null,
};

pub fn isOllamaRunning(io: Io) bool {
    const address = Io.net.IpAddress.parseIp4(ollama_host, ollama_port) catch return false;
    const stream = address.connect(io, .{ .mode = .stream }) catch return false;
    stream.close(io);
    return true;
}

pub fn curateProfileEntry(io: Io, allocator: std.mem.Allocator, p: Profile) !?CuratedProfile {
    const prompt = try templates.buildProfilePrompt(p, allocator);
    defer allocator.free(prompt);
    return curateEntry(io, allocator, prompt, CuratedProfile) catch null;
}

pub fn curateEducationEntry(io: Io, allocator: std.mem.Allocator, e: Education) !?CuratedEducation {
    const prompt = try templates.buildEducationPrompt(e, allocator);
    defer allocator.free(prompt);
    return curateEntry(io, allocator, prompt, CuratedEducation) catch null;
}

pub fn curateExperienceEntry(io: Io, allocator: std.mem.Allocator, e: Experience) !?CuratedExperience {
    const prompt = try templates.buildExperiencePrompt(e, allocator);
    defer allocator.free(prompt);
    return curateEntry(io, allocator, prompt, CuratedExperience) catch null;
}

pub fn curateProjectEntry(io: Io, allocator: std.mem.Allocator, p: Project) !?CuratedProject {
    const prompt = try templates.buildProjectPrompt(p, allocator);
    defer allocator.free(prompt);
    return curateEntry(io, allocator, prompt, CuratedProject) catch null;
}

pub fn curateCertificationEntry(io: Io, allocator: std.mem.Allocator, c: Certification) !?CuratedCertification {
    const prompt = try templates.buildCertificationPrompt(c, allocator);
    defer allocator.free(prompt);
    return curateEntry(io, allocator, prompt, CuratedCertification) catch null;
}

fn curateEntry(io: Io, allocator: std.mem.Allocator, prompt: []const u8, comptime T: type) !T {
    const json_body = try std.fmt.allocPrint(allocator, "{f}", .{std.json.fmt(.{
        .model = model_name,
        .prompt = prompt,
        .stream = false,
    }, .{})});
    defer allocator.free(json_body);

    const raw_response = try sendRequest(io, allocator, json_body);
    defer allocator.free(raw_response);

    const response_text = try extractResponse(raw_response, allocator) orelse return error.OllamaEmpty;
    defer allocator.free(response_text);

    return parseCurated(response_text, allocator, T);
}

fn parseCurated(raw: []const u8, allocator: std.mem.Allocator, comptime T: type) !T {
    const trimmed = std.mem.trim(u8, raw, " \t\r\n");
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, trimmed, .{});
    defer parsed.deinit();

    const root = parsed.value;

    switch (T) {
        CuratedProfile => {
            return CuratedProfile{
                .title = try extractString(root, "title", allocator),
                .summary = try extractString(root, "summary", allocator),
            };
        },
        CuratedEducation => {
            return CuratedEducation{
                .highlights = try extractHighlights(root, allocator),
            };
        },
        CuratedExperience => {
            return CuratedExperience{
                .position = try extractString(root, "position", allocator),
                .description = try extractString(root, "description", allocator),
                .highlights = try extractHighlights(root, allocator),
            };
        },
        CuratedProject => {
            return CuratedProject{
                .description = try extractString(root, "description", allocator),
                .highlights = try extractHighlights(root, allocator),
            };
        },
        CuratedCertification => {
            return CuratedCertification{
                .description = try extractString(root, "description", allocator),
            };
        },
        else => @compileError("unsupported type: " ++ @typeName(T)),
    }
}

fn extractString(value: std.json.Value, field: []const u8, allocator: std.mem.Allocator) !?[]const u8 {
    const val = value.object.get(field) orelse return null;
    return switch (val) {
        .string => |s| try allocator.dupe(u8, s),
        else => null,
    };
}

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

fn contentLength(header: []const u8) ?usize {
    const label = "content-length:";
    if (header.len < label.len) return null;
    const prefix = header[0..label.len];
    if (!std.ascii.eqlIgnoreCase(prefix, label)) return null;

    const value_start = label.len;
    const trimmed = std.mem.trim(u8, header[value_start..], " \t\r");
    return std.fmt.parseInt(usize, trimmed, 10) catch null;
}
