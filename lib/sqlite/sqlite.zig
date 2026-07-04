const std = @import("std");
const builtin = @import("builtin");

pub const Error = error{
    SqliteError,
    OutOfMemory,
    InvalidParam,
};

pub const Db = struct {
    ptr: *c.sqlite3,

    pub fn init(path: []const u8) !Db {
        var db: ?*c.sqlite3 = null;
        const rc = c.sqlite3_open_v2(
            path.ptr,
            &db,
            c.SQLITE_OPEN_READWRITE | c.SQLITE_OPEN_CREATE,
            null,
        );
        if (rc != c.SQLITE_OK) {
            return Error.SqliteError;
        }
        return Db{ .ptr = db.? };
    }

    pub fn deinit(self: *Db) void {
        _ = c.sqlite3_close(self.ptr);
    }

    pub fn lastInsertRowId(self: Db) i64 {
        return c.sqlite3_last_insert_rowid(self.ptr);
    }

    pub fn exec(self: Db, comptime sql: []const u8, options: anytype, params: anytype) !void {
        _ = options;
        var stmt = try self.prepare(sql);
        defer stmt.deinit();
        try bindParams(&stmt, params);
        const rc = c.sqlite3_step(stmt.ptr);
        if (rc != c.SQLITE_DONE and rc != c.SQLITE_ROW) {
            return Error.SqliteError;
        }
    }

    pub fn one(self: Db, allocator: std.mem.Allocator, comptime T: type, comptime sql: []const u8, options: anytype, params: anytype) !?T {
        _ = options;
        var stmt = try self.prepare(sql);
        defer stmt.deinit();
        try bindParams(&stmt, params);
        const rc = c.sqlite3_step(stmt.ptr);
        if (rc == c.SQLITE_DONE) return null;
        if (rc != c.SQLITE_ROW) return Error.SqliteError;
        return @as(?T, try readRow(allocator, T, &stmt, 0));
    }

    pub fn prepare(self: Db, comptime sql: []const u8) !Stmt {
        var stmt: ?*c.sqlite3_stmt = null;
        const rc = c.sqlite3_prepare_v3(
            self.ptr,
            sql.ptr,
            @intCast(sql.len),
            0,
            &stmt,
            null,
        );
        if (rc != c.SQLITE_OK) {
            return Error.SqliteError;
        }
        return Stmt{ .ptr = stmt.? };
    }
};

pub const Stmt = struct {
    ptr: *c.sqlite3_stmt,

    pub fn deinit(self: *Stmt) void {
        _ = c.sqlite3_finalize(self.ptr);
    }

    pub fn step(self: Stmt) !bool {
        const rc = c.sqlite3_step(self.ptr);
        switch (rc) {
            c.SQLITE_ROW => return true,
            c.SQLITE_DONE => return false,
            else => return Error.SqliteError,
        }
    }

    pub fn all(self: Stmt, comptime T: type, allocator: std.mem.Allocator, options: anytype, params: anytype) ![]T {
        _ = options;
        try bindParams(&self, params);
        var list = try std.ArrayList(T).initCapacity(allocator, 0);
        errdefer list.deinit(allocator);
        var row_index: usize = 0;
        while (try self.step()) {
            const row = try readRow(allocator, T, &self, row_index);
            try list.append(allocator, row);
            row_index += 1;
        }
        return list.toOwnedSlice(allocator);
    }
};

fn bindParams(stmt: *const Stmt, params: anytype) !void {
    const T = @TypeOf(params);
    const info = @typeInfo(T);
    var field_index: u32 = 1;
    switch (info) {
        .@"struct" => |s| {
            inline for (s.field_names) |name| {
                const value = @field(params, name);
                try bindValue(stmt, field_index, value);
                field_index += 1;
            }
        },
        else => {
            try bindValue(stmt, 1, params);
        },
    }
}

fn bindValue(stmt: *const Stmt, index: u32, value: anytype) !void {
    const T = @TypeOf(value);
    switch (@typeInfo(T)) {
        .int => {
            const rc = c.sqlite3_bind_int64(stmt.ptr, @intCast(index), @intCast(value));
            if (rc != c.SQLITE_OK) return Error.SqliteError;
        },
        .float => {
            const rc = c.sqlite3_bind_double(stmt.ptr, @intCast(index), @floatCast(value));
            if (rc != c.SQLITE_OK) return Error.SqliteError;
        },
        .optional => {
            if (value) |v| {
                try bindValue(stmt, index, v);
            } else {
                const rc = c.sqlite3_bind_null(stmt.ptr, @intCast(index));
                if (rc != c.SQLITE_OK) return Error.SqliteError;
            }
        },
        .pointer => |ptr| {
            if (ptr.size == .slice and ptr.child == u8) {
                const rc = c.sqlite3_bind_text64(
                    stmt.ptr,
                    @intCast(index),
                    value.ptr,
                    @intCast(value.len),
                    c.SQLITE_TRANSIENT,
                    c.SQLITE_UTF8,
                );
                if (rc != c.SQLITE_OK) return Error.SqliteError;
            }
        },
        else => {},
    }
}

fn readRow(allocator: std.mem.Allocator, comptime T: type, stmt: *const Stmt, row_index: usize) !T {
    _ = row_index;
    var result: T = undefined;
    const info = @typeInfo(T);
    const col_count = c.sqlite3_column_count(stmt.ptr);
    switch (info) {
        .@"struct" => |s| {
            inline for (s.field_names, s.field_types, 0..) |name, FieldType, i| {
                const col_idx = @as(i32, @intCast(i));
                if (col_idx >= col_count) break;
                const col_type = c.sqlite3_column_type(stmt.ptr, col_idx);
                if (col_type == c.SQLITE_NULL) {
                    if (@typeInfo(FieldType) == .optional) {
                        @field(result, name) = @as(FieldType, null);
                    }
                } else {
                    const value = readColumnValue(allocator, FieldType, stmt, col_idx);
                    @field(result, name) = value;
                }
            }
        },
        else => {},
    }
    return result;
}

fn readColumnValue(allocator: std.mem.Allocator, comptime T: type, stmt: *const Stmt, col: i32) T {
    switch (@typeInfo(T)) {
        .int => {
            return @intCast(c.sqlite3_column_int64(stmt.ptr, col));
        },
        .float => {
            return @floatCast(c.sqlite3_column_double(stmt.ptr, col));
        },
        .optional => |opt| {
            if (c.sqlite3_column_type(stmt.ptr, col) == c.SQLITE_NULL) {
                return null;
            }
            return readColumnValue(allocator, opt.child, stmt, col);
        },
        .pointer => |ptr| {
            if (ptr.size == .slice and ptr.child == u8) {
                const bytes = c.sqlite3_column_text(stmt.ptr, col);
                const len = c.sqlite3_column_bytes(stmt.ptr, col);
                const slice = bytes[0..@intCast(len)];
                return @as(T, allocator.dupe(u8, slice) catch @panic("OOM"));
            }
        },
        else => {},
    }
    return undefined;
}

pub const c = struct {
    pub const sqlite3 = opaque {};
    pub const sqlite3_stmt = opaque {};

    pub const SQLITE_OK = 0;
    pub const SQLITE_ROW = 100;
    pub const SQLITE_DONE = 101;
    pub const SQLITE_INTEGER = 1;
    pub const SQLITE_FLOAT = 2;
    pub const SQLITE_TEXT = 3;
    pub const SQLITE_BLOB = 4;
    pub const SQLITE_NULL = 5;
    pub const SQLITE_OPEN_READWRITE = 0x00000002;
    pub const SQLITE_OPEN_CREATE = 0x00000004;
    pub const SQLITE_TRANSIENT: *const anyopaque = @ptrFromInt(@as(usize, std.math.maxInt(usize)));
    pub const SQLITE_UTF8 = @as(u8, 1);

    extern fn sqlite3_open_v2(path: [*]const u8, db: *?*sqlite3, flags: i32, vfs: ?*anyopaque) i32;
    extern fn sqlite3_close(db: *sqlite3) i32;
    extern fn sqlite3_prepare_v3(db: *sqlite3, sql: [*]const u8, nByte: i32, flags: u32, stmt: *?*sqlite3_stmt, tail: ?*?[*]const u8) i32;
    extern fn sqlite3_step(stmt: *sqlite3_stmt) i32;
    extern fn sqlite3_finalize(stmt: *sqlite3_stmt) i32;
    extern fn sqlite3_bind_int64(stmt: *sqlite3_stmt, index: i32, value: i64) i32;
    extern fn sqlite3_bind_double(stmt: *sqlite3_stmt, index: i32, value: f64) i32;
    extern fn sqlite3_bind_text64(stmt: *sqlite3_stmt, index: i32, value: [*]const u8, len: i64, destructor: *const anyopaque, encoding: u8) i32;
    extern fn sqlite3_bind_null(stmt: *sqlite3_stmt, index: i32) i32;
    extern fn sqlite3_column_count(stmt: *const sqlite3_stmt) i32;
    extern fn sqlite3_column_type(stmt: *const sqlite3_stmt, col: i32) i32;
    extern fn sqlite3_column_int64(stmt: *const sqlite3_stmt, col: i32) i64;
    extern fn sqlite3_column_double(stmt: *const sqlite3_stmt, col: i32) f64;
    extern fn sqlite3_column_text(stmt: *const sqlite3_stmt, col: i32) [*]const u8;
    extern fn sqlite3_column_bytes(stmt: *const sqlite3_stmt, col: i32) i32;
    extern fn sqlite3_last_insert_rowid(db: *sqlite3) i64;
    extern fn sqlite3_bind_parameter_index(stmt: *sqlite3_stmt, name: [*]const u8) i32;
    extern fn sqlite3_changes(db: *sqlite3) i32;
    extern fn sqlite3_threadsafe() u32;
};
