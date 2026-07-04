//! Data model types for CV entries.
//!
//! Each struct maps to a database table and carries an optional `id`
//! that is populated after insertion from the auto-increment column.
//! Optional fields use `?[]const u8` so that `null` renders as SQL
//! `NULL` and is omitted during Typst generation.

const std = @import("std");

/// A personal profile — the single top-level identity for the CV.
pub const Profile = struct {
    /// Database row id, assigned after insert.
    id: ?i64 = null,
    /// Full name (required).
    full_name: []const u8,
    email: ?[]const u8 = null,
    phone: ?[]const u8 = null,
    location: ?[]const u8 = null,
    /// Professional title (e.g. "Software Engineer").
    title: ?[]const u8 = null,
    /// Professional summary / objective statement.
    summary: ?[]const u8 = null,
};

/// A degree or educational qualification.
pub const Education = struct {
    id: ?i64 = null,
    /// Institution name (required).
    institution: []const u8,
    degree: ?[]const u8 = null,
    field_of_study: ?[]const u8 = null,
    start_date: ?[]const u8 = null,
    end_date: ?[]const u8 = null,
    gpa: ?[]const u8 = null,
    /// Comma-separated bullet highlights.
    highlights: ?[]const u8 = null,
};

/// A position held at an organisation.
pub const Experience = struct {
    id: ?i64 = null,
    /// Employer name (required).
    company: []const u8,
    position: ?[]const u8 = null,
    location: ?[]const u8 = null,
    start_date: ?[]const u8 = null,
    end_date: ?[]const u8 = null,
    description: ?[]const u8 = null,
    /// Comma-separated bullet highlights.
    highlights: ?[]const u8 = null,
};

/// A side or open-source project.
pub const Project = struct {
    id: ?i64 = null,
    /// Project name (required).
    name: []const u8,
    description: ?[]const u8 = null,
    url: ?[]const u8 = null,
    /// Comma-separated list of technologies used.
    technologies: ?[]const u8 = null,
    start_date: ?[]const u8 = null,
    end_date: ?[]const u8 = null,
    /// Comma-separated bullet highlights.
    highlights: ?[]const u8 = null,
};

/// A skill category with its associated skill list.
pub const Skill = struct {
    id: ?i64 = null,
    /// Category label, e.g. "Programming Languages" (required).
    category: []const u8,
    /// Comma-separated skill names (required).
    skills: []const u8,
};

/// A professional certification or license.
pub const Certification = struct {
    id: ?i64 = null,
    /// Certification name (required).
    name: []const u8,
    issuer: ?[]const u8 = null,
    date: ?[]const u8 = null,
    url: ?[]const u8 = null,
    description: ?[]const u8 = null,
};

/// The six CV sections that can be managed through the CLI.
pub const Category = enum(u8) {
    profile = '1',
    education = '2',
    experience = '3',
    projects = '4',
    skills = '5',
    certifications = '6',

    pub fn fromChar(c: u8) ?Category {
        return switch (c) {
            '1' => .profile,
            '2' => .education,
            '3' => .experience,
            '4' => .projects,
            '5' => .skills,
            '6' => .certifications,
            else => null,
        };
    }

    /// Returns the human-readable label for this category.
    pub fn label(self: Category) []const u8 {
        return switch (self) {
            .profile => "Profile",
            .education => "Education",
            .experience => "Experience",
            .projects => "Projects",
            .skills => "Skills",
            .certifications => "Certifications",
        };
    }
};

test Category {
    try std.testing.expectEqual(@as(?Category, .profile), Category.fromChar('1'));
    try std.testing.expectEqual(@as(?Category, null), Category.fromChar('0'));
    try std.testing.expectEqualStrings("Profile", Category.profile.label());
}
