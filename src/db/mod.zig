const sqlite = @import("sqlite");
const schema = @import("schema.zig");

pub fn init(path: [:0]const u8) !sqlite.Db {
    var db = try sqlite.Db.init(path);
    errdefer db.deinit();
    try schema.createTables(&db);
    return db;
}
