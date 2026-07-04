const std = @import("std");
const sqlite = @import("sqlite");
const types = @import("../types.zig");

const Profile = types.Profile;
const Education = types.Education;
const Experience = types.Experience;
const Project = types.Project;
const Skill = types.Skill;
const Certification = types.Certification;

pub fn insertProfile(db: *sqlite.Db, p: Profile) !void {
    try db.exec(
        \\INSERT INTO profile (full_name, email, phone, location, title, summary)
        \\VALUES (?1, ?2, ?3, ?4, ?5, ?6)
    , .{}, .{ p.full_name, p.email, p.phone, p.location, p.title, p.summary });
}

pub fn getProfile(db: *sqlite.Db) !?Profile {
    const row = try db.one(
        std.heap.page_allocator,
        Profile,
        "SELECT id, full_name, email, phone, location, title, summary FROM profile ORDER BY id DESC LIMIT 1",
        .{}, .{},
    );
    return row;
}

pub fn updateProfile(db: *sqlite.Db, p: Profile) !void {
    try db.exec(
        \\UPDATE profile SET full_name=?1, email=?2, phone=?3, location=?4, title=?5, summary=?6 WHERE id=?7
    , .{}, .{ p.full_name, p.email, p.phone, p.location, p.title, p.summary, p.id });
}

pub fn insertEducation(db: *sqlite.Db, e: Education) !void {
    try db.exec(
        \\INSERT INTO education (institution, degree, field_of_study, start_date, end_date, gpa, highlights)
        \\VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)
    , .{}, .{ e.institution, e.degree, e.field_of_study, e.start_date, e.end_date, e.gpa, e.highlights });
}

pub fn getAllEducation(db: *sqlite.Db) ![]Education {
    var stmt = try db.prepare("SELECT id, institution, degree, field_of_study, start_date, end_date, gpa, highlights FROM education ORDER BY start_date DESC");
    defer stmt.deinit();
    return stmt.all(Education, std.heap.page_allocator, .{}, .{});
}

pub fn updateEducation(db: *sqlite.Db, e: Education) !void {
    try db.exec(
        \\UPDATE education SET institution=?1, degree=?2, field_of_study=?3, start_date=?4, end_date=?5, gpa=?6, highlights=?7 WHERE id=?8
    , .{}, .{ e.institution, e.degree, e.field_of_study, e.start_date, e.end_date, e.gpa, e.highlights, e.id });
}

pub fn deleteEducation(db: *sqlite.Db, id: i64) !void {
    try db.exec("DELETE FROM education WHERE id=?1", .{}, .{id});
}

pub fn insertExperience(db: *sqlite.Db, e: Experience) !void {
    try db.exec(
        \\INSERT INTO experience (company, position, location, start_date, end_date, description, highlights)
        \\VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)
    , .{}, .{ e.company, e.position, e.location, e.start_date, e.end_date, e.description, e.highlights });
}

pub fn getAllExperience(db: *sqlite.Db) ![]Experience {
    var stmt = try db.prepare("SELECT id, company, position, location, start_date, end_date, description, highlights FROM experience ORDER BY start_date DESC");
    defer stmt.deinit();
    return stmt.all(Experience, std.heap.page_allocator, .{}, .{});
}

pub fn updateExperience(db: *sqlite.Db, e: Experience) !void {
    try db.exec(
        \\UPDATE experience SET company=?1, position=?2, location=?3, start_date=?4, end_date=?5, description=?6, highlights=?7 WHERE id=?8
    , .{}, .{ e.company, e.position, e.location, e.start_date, e.end_date, e.description, e.highlights, e.id });
}

pub fn deleteExperience(db: *sqlite.Db, id: i64) !void {
    try db.exec("DELETE FROM experience WHERE id=?1", .{}, .{id});
}

pub fn insertProject(db: *sqlite.Db, p: Project) !void {
    try db.exec(
        \\INSERT INTO projects (name, description, url, technologies, start_date, end_date, highlights)
        \\VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)
    , .{}, .{ p.name, p.description, p.url, p.technologies, p.start_date, p.end_date, p.highlights });
}

pub fn getAllProjects(db: *sqlite.Db) ![]Project {
    var stmt = try db.prepare("SELECT id, name, description, url, technologies, start_date, end_date, highlights FROM projects ORDER BY start_date DESC");
    defer stmt.deinit();
    return stmt.all(Project, std.heap.page_allocator, .{}, .{});
}

pub fn updateProject(db: *sqlite.Db, p: Project) !void {
    try db.exec(
        \\UPDATE projects SET name=?1, description=?2, url=?3, technologies=?4, start_date=?5, end_date=?6, highlights=?7 WHERE id=?8
    , .{}, .{ p.name, p.description, p.url, p.technologies, p.start_date, p.end_date, p.highlights, p.id });
}

pub fn deleteProject(db: *sqlite.Db, id: i64) !void {
    try db.exec("DELETE FROM projects WHERE id=?1", .{}, .{id});
}

pub fn insertSkill(db: *sqlite.Db, s: Skill) !void {
    try db.exec(
        "INSERT INTO skills (category, skills) VALUES (?1, ?2)",
    .{}, .{ s.category, s.skills });
}

pub fn getAllSkills(db: *sqlite.Db) ![]Skill {
    var stmt = try db.prepare("SELECT id, category, skills FROM skills");
    defer stmt.deinit();
    return stmt.all(Skill, std.heap.page_allocator, .{}, .{});
}

pub fn updateSkill(db: *sqlite.Db, s: Skill) !void {
    try db.exec(
        "UPDATE skills SET category=?1, skills=?2 WHERE id=?3",
    .{}, .{ s.category, s.skills, s.id });
}

pub fn deleteSkill(db: *sqlite.Db, id: i64) !void {
    try db.exec("DELETE FROM skills WHERE id=?1", .{}, .{id});
}

pub fn insertCertification(db: *sqlite.Db, c: Certification) !void {
    try db.exec(
        \\INSERT INTO certifications (name, issuer, date, url, description)
        \\VALUES (?1, ?2, ?3, ?4, ?5)
    , .{}, .{ c.name, c.issuer, c.date, c.url, c.description });
}

pub fn getAllCertifications(db: *sqlite.Db) ![]Certification {
    var stmt = try db.prepare("SELECT id, name, issuer, date, url, description FROM certifications");
    defer stmt.deinit();
    return stmt.all(Certification, std.heap.page_allocator, .{}, .{});
}

pub fn updateCertification(db: *sqlite.Db, c: Certification) !void {
    try db.exec(
        "UPDATE certifications SET name=?1, issuer=?2, date=?3, url=?4, description=?5 WHERE id=?6",
    .{}, .{ c.name, c.issuer, c.date, c.url, c.description, c.id });
}

pub fn deleteCertification(db: *sqlite.Db, id: i64) !void {
    try db.exec("DELETE FROM certifications WHERE id=?1", .{}, .{id});
}
