const sqlite = @import("sqlite");

pub fn createTables(db: *sqlite.Db) !void {
    try db.exec(
        \\CREATE TABLE IF NOT EXISTS profile (
        \\  id INTEGER PRIMARY KEY AUTOINCREMENT,
        \\  full_name TEXT NOT NULL,
        \\  email TEXT,
        \\  phone TEXT,
        \\  location TEXT,
        \\  title TEXT,
        \\  summary TEXT
        \\)
    , .{}, .{});

    try db.exec(
        \\CREATE TABLE IF NOT EXISTS education (
        \\  id INTEGER PRIMARY KEY AUTOINCREMENT,
        \\  institution TEXT NOT NULL,
        \\  degree TEXT,
        \\  field_of_study TEXT,
        \\  start_date TEXT,
        \\  end_date TEXT,
        \\  gpa TEXT,
        \\  highlights TEXT
        \\)
    , .{}, .{});

    try db.exec(
        \\CREATE TABLE IF NOT EXISTS experience (
        \\  id INTEGER PRIMARY KEY AUTOINCREMENT,
        \\  company TEXT NOT NULL,
        \\  position TEXT,
        \\  location TEXT,
        \\  start_date TEXT,
        \\  end_date TEXT,
        \\  description TEXT,
        \\  highlights TEXT
        \\)
    , .{}, .{});

    try db.exec(
        \\CREATE TABLE IF NOT EXISTS projects (
        \\  id INTEGER PRIMARY KEY AUTOINCREMENT,
        \\  name TEXT NOT NULL,
        \\  description TEXT,
        \\  url TEXT,
        \\  technologies TEXT,
        \\  start_date TEXT,
        \\  end_date TEXT,
        \\  highlights TEXT
        \\)
    , .{}, .{});

    try db.exec(
        \\CREATE TABLE IF NOT EXISTS skills (
        \\  id INTEGER PRIMARY KEY AUTOINCREMENT,
        \\  category TEXT NOT NULL,
        \\  skills TEXT NOT NULL
        \\)
    , .{}, .{});

    try db.exec(
        \\CREATE TABLE IF NOT EXISTS certifications (
        \\  id INTEGER PRIMARY KEY AUTOINCREMENT,
        \\  name TEXT NOT NULL,
        \\  issuer TEXT,
        \\  date TEXT,
        \\  url TEXT,
        \\  description TEXT
        \\)
    , .{}, .{});
}
