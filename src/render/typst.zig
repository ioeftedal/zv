const std = @import("std");
const types = @import("../types.zig");

const Profile = types.Profile;
const Education = types.Education;
const Experience = types.Experience;
const Project = types.Project;
const Skill = types.Skill;
const Certification = types.Certification;

const ListWriter = struct {
    list: *std.ArrayList(u8),
    allocator: std.mem.Allocator,

    fn writeAll(self: *ListWriter, data: []const u8) !void {
        try self.list.appendSlice(self.allocator, data);
    }

    fn print(self: *ListWriter, comptime fmt: []const u8, args: anytype) !void {
        const s = try std.fmt.allocPrint(self.allocator, fmt, args);
        defer self.allocator.free(s);
        try self.list.appendSlice(self.allocator, s);
    }
};

pub fn generateTypst(
    profile: ?Profile,
    education: []const Education,
    experience: []const Experience,
    projects: []const Project,
    skills: []const Skill,
    certifications: []const Certification,
    allocator: std.mem.Allocator,
) ![]u8 {
    var buf = try std.ArrayList(u8).initCapacity(allocator, 4096);
    var w = ListWriter{ .list = &buf, .allocator = allocator };

    try w.writeAll("#import \"@preview/basic-resume:0.2.9\": *\n\n");

    const name = if (profile) |p| p.full_name else "Your Name";
    const email = if (profile) |p| p.email orelse "" else "";
    const phone = if (profile) |p| p.phone orelse "" else "";
    const location = if (profile) |p| p.location orelse "" else "";
    const summary = if (profile) |p| p.summary orelse "" else "";

    try w.print("#let name = \"{s}\"\n", .{name});
    if (location.len > 0) try w.print("#let location = \"{s}\"\n", .{location});
    if (email.len > 0) try w.print("#let email = \"{s}\"\n", .{email});
    if (phone.len > 0) try w.print("#let phone = \"{s}\"\n", .{phone});
    try w.writeAll("\n");

    try w.writeAll("#show: resume.with(\n");
    try w.writeAll("  author: name,\n");
    if (location.len > 0) try w.writeAll("  location: location,\n");
    if (email.len > 0) try w.writeAll("  email: email,\n");
    if (phone.len > 0) try w.writeAll("  phone: phone,\n");
    try w.writeAll("  accent-color: \"#26428b\",\n");
    try w.writeAll("  font: \"New Computer Modern\",\n");
    try w.writeAll("  paper: \"us-letter\",\n");
    try w.writeAll("  author-position: left,\n");
    try w.writeAll("  personal-info-position: left,\n");
    try w.writeAll(")\n\n");

    if (summary.len > 0) {
        try w.writeAll("== Summary\n\n");
        try w.print("{s}\n\n", .{summary});
    }

    if (education.len > 0) {
        try w.writeAll("== Education\n\n");
        for (education) |e| {
            try w.writeAll("#edu(\n");
            try w.print("  institution: \"{s}\",\n", .{escape(e.institution)});
            if (e.degree) |v| try w.print("  degree: \"{s}\",\n", .{escape(v)});
            if (e.start_date) |s| {
                const end = e.end_date orelse "";
                try w.print("  dates: dates-helper(start-date: \"{s}\", end-date: \"{s}\"),\n", .{ escape(s), escape(end) });
            }
            if (e.gpa) |v| try w.print("  gpa: \"{s}\",\n", .{escape(v)});
            try w.writeAll(")\n\n");
        }
    }

    if (experience.len > 0) {
        try w.writeAll("== Work Experience\n\n");
        for (experience) |e| {
            try w.writeAll("#work(\n");
            try w.print("  company: \"{s}\",\n", .{escape(e.company)});
            if (e.position) |v| try w.print("  title: \"{s}\",\n", .{escape(v)});
            if (e.location) |v| try w.print("  location: \"{s}\",\n", .{escape(v)});
            if (e.start_date) |s| {
                const end = e.end_date orelse "";
                try w.print("  dates: dates-helper(start-date: \"{s}\", end-date: \"{s}\"),\n", .{ escape(s), escape(end) });
            }
            try w.writeAll(")\n\n");
            if (e.description) |v| {
                try w.print("{s}\n\n", .{v});
            }
            if (e.highlights) |v| {
                var iter = std.mem.splitScalar(u8, v, ',');
                while (iter.next()) |item| {
                    const trimmed = std.mem.trim(u8, item, " ");
                    if (trimmed.len > 0) {
                        try w.print("- {s}\n", .{trimmed});
                    }
                }
                try w.writeAll("\n");
            }
        }
    }

    if (projects.len > 0) {
        try w.writeAll("== Projects\n\n");
        for (projects) |p| {
            try w.writeAll("#project(\n");
            try w.print("  name: \"{s}\",\n", .{escape(p.name)});
            if (p.url) |v| try w.print("  url: \"{s}\",\n", .{escape(v)});
            if (p.start_date) |s| {
                const end = p.end_date orelse "";
                try w.print("  dates: dates-helper(start-date: \"{s}\", end-date: \"{s}\"),\n", .{ escape(s), escape(end) });
            }
            try w.writeAll(")\n\n");
            if (p.description) |v| {
                try w.print("{s}\n\n", .{v});
            }
            if (p.highlights) |v| {
                var iter = std.mem.splitScalar(u8, v, ',');
                while (iter.next()) |item| {
                    const trimmed = std.mem.trim(u8, item, " ");
                    if (trimmed.len > 0) {
                        try w.print("- {s}\n", .{trimmed});
                    }
                }
                try w.writeAll("\n");
            }
        }
    }

    if (skills.len > 0) {
        try w.writeAll("== Skills\n\n");
        for (skills) |s| {
            try w.print("#generic-one-by-two(left: \"{s}\", right: \"{s}\")\n\n", .{ escape(s.category), escape(s.skills) });
        }
    }

    if (certifications.len > 0) {
        try w.writeAll("== Certifications\n\n");
        for (certifications) |c| {
            try w.writeAll("#certificates(\n");
            try w.print("  name: \"{s}\",\n", .{escape(c.name)});
            if (c.issuer) |v| try w.print("  issuer: \"{s}\",\n", .{escape(v)});
            if (c.url) |v| try w.print("  url: \"{s}\",\n", .{escape(v)});
            if (c.date) |v| try w.print("  date: \"{s}\",\n", .{escape(v)});
            try w.writeAll(")\n\n");
        }
    }

    return try buf.toOwnedSlice(allocator);
}

fn escape(s: []const u8) []const u8 {
    return s;
}
