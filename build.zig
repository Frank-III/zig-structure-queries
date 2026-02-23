const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Get SQLite dependency
    const sqlite_dep = b.dependency("sqlite", .{
        .target = target,
        .optimize = optimize,
    });

    // Main library module
    const zsq_module = b.addModule("zsq", .{
        .root_source_file = b.path("src/zsq.zig"),
    });
    zsq_module.addImport("sqlite", sqlite_dep.module("sqlite"));

    // Create test executable using root_module
    const lib_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/zsq.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    lib_tests.root_module.addImport("sqlite", sqlite_dep.module("sqlite"));

    const run_lib_tests = b.addRunArtifact(lib_tests);

    // Add test step
    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&run_lib_tests.step);

    // Build examples
    const examples = [_][]const u8{
        "basic",
        "advanced",
        "joins",
        "join_summary",
        "database_demo",
        "sqlite_demo",
        "ergonomic_api_demo",
    };

    for (examples) |example| {
        const example_module = b.createModule(.{
            .root_source_file = b.path(b.fmt("examples/{s}.zig", .{example})),
            .target = target,
            .optimize = optimize,
        });
        example_module.addImport("zsq", zsq_module);
        example_module.addImport("sqlite", sqlite_dep.module("sqlite"));

        const example_exe = b.addExecutable(.{
            .name = example,
            .root_module = example_module,
        });

        const install_example = b.addInstallArtifact(example_exe, .{});
        b.getInstallStep().dependOn(&install_example.step);

        const run_example = b.addRunArtifact(example_exe);
        const run_step = b.step(b.fmt("run-{s}", .{example}), b.fmt("Run {s} example", .{example}));
        run_step.dependOn(&run_example.step);
    }
}
