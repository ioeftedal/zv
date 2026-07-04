//! A thin adapter that lets an `ArrayList(u8)` serve as an `Io.Writer`.
//!
//! Both `writeAll` and `print` append to the underlying list so that
//! callers can build up a string incrementally without manual buffer
//! management.

const std = @import("std");

/// Wraps an `ArrayList(u8)` with two convenience methods that match
/// the `Io.Writer` interface.
pub const ListWriter = struct {
    list: *std.ArrayList(u8),
    allocator: std.mem.Allocator,

    pub fn writeAll(self: *ListWriter, data: []const u8) !void {
        try self.list.appendSlice(self.allocator, data);
    }

    pub fn print(self: *ListWriter, comptime fmt: []const u8, args: anytype) !void {
        const s = try std.fmt.allocPrint(self.allocator, fmt, args);
        defer self.allocator.free(s);
        try self.list.appendSlice(self.allocator, s);
    }
};
