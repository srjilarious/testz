const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const tree_sitter_dep = b.dependency("tree_sitter", .{
        .target = target,
        .optimize = optimize,
    });
    const tree_sitter_zig_dep = b.dependency("tree_sitter_zig", .{
        .target = target,
        .optimize = optimize,
        .@"build-shared" = false,
    });

    const highlight_ansi_mod = b.addModule("highlight_ansi", .{
        .root_source_file = b.path("src/highlight_ansi.zig"),
    });
    highlight_ansi_mod.addImport("tree_sitter", tree_sitter_dep.module("tree_sitter"));
    highlight_ansi_mod.addImport("tree-sitter-zig", tree_sitter_zig_dep.module("tree-sitter-zig"));

    const testzMod = b.addModule("testz", .{
        .root_source_file = b.path("src/testz.zig"),
    });
    testzMod.addImport("highlight_ansi", highlight_ansi_mod);

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
    exe.root_module.addImport("highlight_ansi", highlight_ansi_mod);

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("tests", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
