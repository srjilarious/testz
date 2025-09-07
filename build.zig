const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const testzMod = b.addModule("testz", .{
        .root_source_file = b.path("src/testz.zig"),
    });

    const exe = b.addExecutable(.{
        .name = "testz_main",
        .root_module = b.addModule("main", .{
            .root_source_file = b.path("tests/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    // exe.use_llvm = true; // Force LLVM backend for debugging.
    exe.root_module.addImport("testz", testzMod);

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("tests", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
