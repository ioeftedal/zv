//! Thin Zig bindings over the SQLite3 C API.
//!
//! Provides a minimal but type-safe wrapper: comptime reflection maps
//! struct fields to `?`-numbered parameters and reads rows back into
//! typed Zig structs.  Only SQLite3 amalgamation (``sqlite3.c``) is
//! supported; the C functions are declared as `extern` in the `c`
//! namespace at the bottom of this file.

const std = @import("std");

/// All SQLite errors are collapsed into a single variant.
///
/// The underlying error message can be retrieved through
/// `Db.errMsg`.
pub const Error = error{
    SqliteError,
};

/// An open SQLite3 database connection.
pub const Db = struct {
    ptr: *c.sqlite3,

    /// Open (or create) the database at `path` with read/write access.
    pub fn init(path: [:0]const u8) Error!Db {
        var db: ?*c.sqlite3 = null;
        const rc = c.sqlite3_open_v2(
            path.ptr,
            &db,
            c.SQLITE_OPEN_READWRITE | c.SQLITE_OPEN_CREATE,
            null,
        );
        if (rc != c.SQLITE_OK) {
            std.log.err("sqlite3_open_v2 failed", .{});
            return Error.SqliteError;
        }
        return Db{ .ptr = db.? };
    }

    pub fn deinit(self: *Db) void {
        _ = c.sqlite3_close(self.ptr);
    }

    /// Return the most recent error message for this connection.
    pub fn errMsg(self: *const Db) []const u8 {
        return std.mem.sliceTo(c.sqlite3_errmsg(self.ptr), 0);
    }

    fn logErr(self: *const Db) void {
        std.log.err("sqlite error: {s}", .{self.errMsg()});
    }

    /// Execute a SQL statement that does not return rows.
    ///
    /// `params` may be a struct (fields map to `?1`, `?2`, … by field
    /// order) or a single scalar value.
    pub fn exec(self: *Db, comptime sql: []const u8, params: anytype) Error!void {
        var stmt = try self.prepare(sql);
        defer stmt.deinit();
        try bindParams(&stmt, params);
        const rc = c.sqlite3_step(stmt.ptr);
        if (rc != c.SQLITE_DONE and rc != c.SQLITE_ROW) {
            self.logErr();
            return Error.SqliteError;
        }
    }

    /// Execute a query and return at most one row of type `T`, or
    /// `null` if no rows match.
    pub fn one(self: *Db, allocator: std.mem.Allocator, comptime T: type, comptime sql: []const u8, params: anytype) (Error || std.mem.Allocator.Error)!?T {
        var stmt = try self.prepare(sql);
        defer stmt.deinit();
        try bindParams(&stmt, params);
        const rc = c.sqlite3_step(stmt.ptr);
        if (rc == c.SQLITE_DONE) return null;
        if (rc != c.SQLITE_ROW) {
            self.logErr();
            return Error.SqliteError;
        }
        return try readRow(allocator, T, &stmt);
    }

    /// Prepare a SQL statement for repeated execution.
    pub fn prepare(self: *Db, comptime sql: []const u8) Error!Stmt {
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
            self.logErr();
            return Error.SqliteError;
        }
        return Stmt{ .ptr = stmt.?, .db = self.ptr };
    }
};

/// A prepared SQL statement.  Must be finalised with `deinit`.
pub const Stmt = struct {
    ptr: *c.sqlite3_stmt,
    db: *c.sqlite3,

    pub fn deinit(self: *Stmt) void {
        _ = c.sqlite3_finalize(self.ptr);
    }

    /// Advance the statement to the next row.
    ///
    /// Returns `true` if a row is available, `false` when done.
    pub fn step(self: *Stmt) Error!bool {
        const rc = c.sqlite3_step(self.ptr);
        switch (rc) {
            c.SQLITE_ROW => return true,
            c.SQLITE_DONE => return false,
            else => {
                std.log.err("sqlite step error: {s}", .{std.mem.sliceTo(c.sqlite3_errmsg(self.db), 0)});
                return Error.SqliteError;
            },
        }
    }

    /// Bind parameters, iterate all result rows, and return them as a
    /// typed slice.  The slice and any string fields are allocated with
    /// `allocator`.
    pub fn all(self: *Stmt, comptime T: type, allocator: std.mem.Allocator, params: anytype) (Error || std.mem.Allocator.Error)![]T {
        try bindParams(self, params);
        var list = try std.ArrayList(T).initCapacity(allocator, 0);
        errdefer list.deinit(allocator);
        while (try self.step()) {
            const row = try readRow(allocator, T, self);
            try list.append(allocator, row);
        }
        return try list.toOwnedSlice(allocator);
    }
};

/// Bind struct fields or a scalar value to positional parameters.
fn bindParams(stmt: *const Stmt, params: anytype) Error!void {
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

/// Bind a single value at the given `?N` index.
///
/// Supports `int`, `float`, `?T`, and `[]const u8`.
fn bindValue(stmt: *const Stmt, index: u32, value: anytype) Error!void {
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
        else => @compileError("unsupported type for SQL bind: " ++ @typeName(T)),
    }
}

/// Read the current row of `stmt` into a value of type `T`.
///
/// Columns are mapped to struct fields positionally.
fn readRow(allocator: std.mem.Allocator, comptime T: type, stmt: *const Stmt) (Error || std.mem.Allocator.Error)!T {
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
                    const value = try readColumnValue(allocator, FieldType, stmt, col_idx);
                    @field(result, name) = value;
                }
            }
        },
        else => @compileError("readRow requires a struct type, got " ++ @typeName(T)),
    }
    return result;
}

/// Read a single column value into a Zig type.
///
/// Handles `int`, `float`, `?T`, and `[]const u8` (allocated via
/// `allocator`).
fn readColumnValue(allocator: std.mem.Allocator, comptime T: type, stmt: *const Stmt, col: i32) (Error || std.mem.Allocator.Error)!T {
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
            return try readColumnValue(allocator, opt.child, stmt, col);
        },
        .pointer => |ptr| {
            if (ptr.size == .slice and ptr.child == u8) {
                const bytes = c.sqlite3_column_text(stmt.ptr, col);
                const len = c.sqlite3_column_bytes(stmt.ptr, col);
                const slice = bytes[0..@intCast(len)];
                return try allocator.dupe(u8, slice);
            }
        },
        else => @compileError("unsupported type for SQL column read: " ++ @typeName(T)),
    }
}

/// Raw C API declarations from the SQLite3 amalgamation.
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
    extern fn sqlite3_errmsg(db: *const sqlite3) [*:0]const u8;
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
};
