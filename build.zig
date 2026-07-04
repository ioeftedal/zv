const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const sqlite_amalgamation_dep = b.dependency("sqlite_amalgamation", .{
        .target = target,
        .optimize = optimize,
    });

    const sqlite_module = b.createModule(.{
        .root_source_file = b.path("src/sqlite.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    const exe = b.addExecutable(.{
        .name = "cv",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "sqlite", .module = sqlite_module },
            },
        }),
    });
    exe.root_module.link_libc = true;
    exe.root_module.addCSourceFile(.{
        .file = sqlite_amalgamation_dep.path("sqlite3.c"),
        .flags = &.{
            "-std=c99",
            "-DSQLITE_ENABLE_FTS5",
            "-DSQLITE_THREADSAFE=1",
        },
    });
    exe.root_module.addIncludePath(sqlite_amalgamation_dep.path("."));

    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());
    run_cmd.addPassthruArgs();

    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });
    const run_exe_tests = b.addRunArtifact(exe_tests);
    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_exe_tests.step);
}
