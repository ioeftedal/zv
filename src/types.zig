pub const Profile = struct {
    id: ?i64 = null,
    full_name: []const u8,
    email: ?[]const u8 = null,
    phone: ?[]const u8 = null,
    location: ?[]const u8 = null,
    title: ?[]const u8 = null,
    summary: ?[]const u8 = null,
};

pub const Education = struct {
    id: ?i64 = null,
    institution: []const u8,
    degree: ?[]const u8 = null,
    field_of_study: ?[]const u8 = null,
    start_date: ?[]const u8 = null,
    end_date: ?[]const u8 = null,
    gpa: ?[]const u8 = null,
    highlights: ?[]const u8 = null,
};

pub const Experience = struct {
    id: ?i64 = null,
    company: []const u8,
    position: ?[]const u8 = null,
    location: ?[]const u8 = null,
    start_date: ?[]const u8 = null,
    end_date: ?[]const u8 = null,
    description: ?[]const u8 = null,
    highlights: ?[]const u8 = null,
};

pub const Project = struct {
    id: ?i64 = null,
    name: []const u8,
    description: ?[]const u8 = null,
    url: ?[]const u8 = null,
    technologies: ?[]const u8 = null,
    start_date: ?[]const u8 = null,
    end_date: ?[]const u8 = null,
    highlights: ?[]const u8 = null,
};

pub const Skill = struct {
    id: ?i64 = null,
    category: []const u8,
    skills: []const u8,
};

pub const Certification = struct {
    id: ?i64 = null,
    name: []const u8,
    issuer: ?[]const u8 = null,
    date: ?[]const u8 = null,
    url: ?[]const u8 = null,
    description: ?[]const u8 = null,
};

pub const Category = enum {
    profile,
    education,
    experience,
    projects,
    skills,
    certifications,

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
