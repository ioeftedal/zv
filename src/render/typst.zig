//! Typst source code generator.
//!
//! Takes CV data structures and produces a `.typ` file compatible with
//! the `@preview/basic-resume:0.2.9` template package.  Special
//! characters (`\`, `"`, `#`, `{`, `}`) are escaped for Typst.

const std = @import("std");
const types = @import("../types.zig");
const writer = @import("../writer.zig");

const Profile = types.Profile;
const Education = types.Education;
const Experience = types.Experience;
const Project = types.Project;
const Skill = types.Skill;
const Certification = types.Certification;

/// Produce the complete Typst source for a CV.
///
/// Each section is rendered as a Typst heading and corresponding
/// template function calls (`#edu`, `#work`, `#project`,
/// `#certificates`, `#generic-one-by-two`).  The returned slice is
/// owned by the caller.
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
    var w = writer.ListWriter{ .list = &buf, .allocator = allocator };

    try w.writeAll("#import \"@preview/basic-resume:0.2.9\": *\n\n");

    if (profile) |p| {
        const name_esc = try escape(allocator, p.full_name);
        try w.print("#let name = \"{s}\"\n", .{name_esc});
        if (p.email) |v| {
            const v_esc = try escape(allocator, v);
            try w.print("#let email = \"{s}\"\n", .{v_esc});
        }
        if (p.phone) |v| {
            const v_esc = try escape(allocator, v);
            try w.print("#let phone = \"{s}\"\n", .{v_esc});
        }
        if (p.location) |v| {
            const v_esc = try escape(allocator, v);
            try w.print("#let location = \"{s}\"\n", .{v_esc});
        }
        const summary = p.summary orelse "";
        try w.writeAll("\n");
        try w.writeAll("#show: resume.with(\n");
        try w.print("  author: name,\n", .{});
        if (p.location != null) try w.writeAll("  location: location,\n");
        if (p.email != null) try w.writeAll("  email: email,\n");
        if (p.phone != null) try w.writeAll("  phone: phone,\n");
        try w.writeAll("  accent-color: \"#26428b\",\n");
        try w.writeAll("  font: \"New Computer Modern\",\n");
        try w.writeAll("  paper: \"us-letter\",\n");
        try w.writeAll("  author-position: left,\n");
        try w.writeAll("  personal-info-position: left,\n");
        try w.writeAll(")\n\n");

        if (summary.len > 0) {
            try w.writeAll("== Summary\n\n");
            const summary_esc = try escape(allocator, summary);
            try w.print("{s}\n\n", .{summary_esc});
        }
    }

    if (education.len > 0) {
        try w.writeAll("== Education\n\n");
        for (education) |e| {
            try w.writeAll("#edu(\n");
            {
                const v = try escape(allocator, e.institution);
                try w.print("  institution: \"{s}\",\n", .{v});
            }
            if (e.degree) |v| {
                const v_esc = try escape(allocator, v);
                try w.print("  degree: \"{s}\",\n", .{v_esc});
            }
            if (e.start_date) |s| {
                const end = e.end_date orelse "";
                const s_esc = try escape(allocator, s);
                const end_esc = try escape(allocator, end);
                try w.print("  dates: dates-helper(start-date: \"{s}\", end-date: \"{s}\"),\n", .{ s_esc, end_esc });
            }
            if (e.gpa) |v| {
                const v_esc = try escape(allocator, v);
                try w.print("  gpa: \"{s}\",\n", .{v_esc});
            }
            try w.writeAll(")\n\n");
        }
    }

    if (experience.len > 0) {
        try w.writeAll("== Work Experience\n\n");
        for (experience) |e| {
            try w.writeAll("#work(\n");
            {
                const v = try escape(allocator, e.company);
                try w.print("  company: \"{s}\",\n", .{v});
            }
            if (e.position) |v| {
                const v_esc = try escape(allocator, v);
                try w.print("  title: \"{s}\",\n", .{v_esc});
            }
            if (e.location) |v| {
                const v_esc = try escape(allocator, v);
                try w.print("  location: \"{s}\",\n", .{v_esc});
            }
            if (e.start_date) |s| {
                const end = e.end_date orelse "";
                const s_esc = try escape(allocator, s);
                const end_esc = try escape(allocator, end);
                try w.print("  dates: dates-helper(start-date: \"{s}\", end-date: \"{s}\"),\n", .{ s_esc, end_esc });
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
            {
                const v = try escape(allocator, p.name);
                try w.print("  name: \"{s}\",\n", .{v});
            }
            if (p.url) |v| {
                const v_esc = try escape(allocator, v);
                try w.print("  url: \"{s}\",\n", .{v_esc});
            }
            if (p.start_date) |s| {
                const end = p.end_date orelse "";
                const s_esc = try escape(allocator, s);
                const end_esc = try escape(allocator, end);
                try w.print("  dates: dates-helper(start-date: \"{s}\", end-date: \"{s}\"),\n", .{ s_esc, end_esc });
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
            const cat_esc = try escape(allocator, s.category);
            const skills_esc = try escape(allocator, s.skills);
            try w.print("#generic-one-by-two(left: \"{s}\", right: \"{s}\")\n\n", .{ cat_esc, skills_esc });
        }
    }

    if (certifications.len > 0) {
        try w.writeAll("== Certifications\n\n");
        for (certifications) |c| {
            try w.writeAll("#certificates(\n");
            {
                const v = try escape(allocator, c.name);
                try w.print("  name: \"{s}\",\n", .{v});
            }
            if (c.issuer) |v| {
                const v_esc = try escape(allocator, v);
                try w.print("  issuer: \"{s}\",\n", .{v_esc});
            }
            if (c.url) |v| {
                const v_esc = try escape(allocator, v);
                try w.print("  url: \"{s}\",\n", .{v_esc});
            }
            if (c.date) |v| {
                const v_esc = try escape(allocator, v);
                try w.print("  date: \"{s}\",\n", .{v_esc});
            }
            try w.writeAll(")\n\n");
        }
    }

    return try buf.toOwnedSlice(allocator);
}

/// Escape Typst special characters with a backslash prefix.
///
/// The escaped characters are: `\`, `"`, `#`, `{`, `}`.
fn escape(allocator: std.mem.Allocator, s: []const u8) ![]u8 {
    var extra: usize = 0;
    for (s) |c| {
        switch (c) {
            '\\', '"', '#', '{', '}' => extra += 1,
            else => {},
        }
    }
    if (extra == 0) return try allocator.dupe(u8, s);

    var result = try std.ArrayList(u8).initCapacity(allocator, s.len + extra);
    for (s) |c| {
        switch (c) {
            '\\', '"', '#', '{', '}' => {
                try result.append(allocator, '\\');
                try result.append(allocator, c);
            },
            else => try result.append(allocator, c),
        }
    }
    return try result.toOwnedSlice(allocator);
}
