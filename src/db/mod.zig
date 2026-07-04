//! Database initialisation and lifecycle.
//!
//! Opens (or creates) the SQLite database file and ensures all
//! required tables exist before returning the connection handle.

const sqlite = @import("sqlite");
const schema = @import("schema.zig");

/// Open a database at `path`, creating tables if they do not exist.
///
/// The caller owns the returned `sqlite.Db` and must call `deinit` on it.
pub fn init(path: [:0]const u8) !sqlite.Db {
    var db = try sqlite.Db.init(path);
    errdefer db.deinit();
    try schema.createTables(&db);
    return db;
}
