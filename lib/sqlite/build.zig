const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const sqlite_dep = b.dependency("sqlite", .{
        .target = target,
        .optimize = optimize,
    });

    const lib = b.addLibrary(.{
        .name = "sqlite",
        .linkage = .static,
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });
    lib.root_module.addCSourceFile(.{
        .file = sqlite_dep.path("sqlite3.c"),
        .flags = &.{
            "-std=c99",
            "-DSQLITE_ENABLE_FTS5",
            "-DSQLITE_THREADSAFE=1",
        },
    });
    lib.root_module.addIncludePath(sqlite_dep.path("."));

    const mod = b.addModule("sqlite", .{
        .root_source_file = b.path("sqlite.zig"),
        .link_libc = true,
    });
    mod.addIncludePath(sqlite_dep.path("."));
    mod.linkLibrary(lib);

    b.installArtifact(lib);
}
