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

    const tests_mod = b.createModule(.{
        .root_source_file = b.path("tests/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    tests_mod.addImport("highlight_ansi", highlight_ansi_mod);
    const exe = buildTestExe(b, target, optimize, testzMod, "testz_main", tests_mod);
    // exe.use_llvm = true; // Force LLVM backend for debugging.

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    run_cmd.addPassthruArgs();

    const run_step = b.step("tests", "Run the app");
    run_step.dependOn(&run_cmd.step);
}

/// Options for `addTestExe`.
pub const TestExeOptions = struct {
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    /// The testz dependency, e.g. `b.dependency("testz", .{ .target = target })`.
    testz_dep: *std.Build.Dependency,
    /// The executable's name.
    name: []const u8,
    /// The test runner's root module: the one whose `main` calls
    /// `testz.testzRunner`.  It gets a `testz` import added.
    root_module: *std.Build.Module,
};

/// Builds a test runner executable against the testz dependency.  The
/// executable's root is a small generated module that installs
/// `testz.panic`, so a panic inside a test prints its message instead of
/// losing it in the output capture pipe, then delegates to
/// `root_module.main`.  A `panic` or `std_options` declared in
/// `root_module` is forwarded and takes precedence.
pub fn addTestExe(b: *std.Build, opts: TestExeOptions) *std.Build.Step.Compile {
    return buildTestExe(b, opts.target, opts.optimize, opts.testz_dep.module("testz"), opts.name, opts.root_module);
}

fn buildTestExe(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    testz_mod: *std.Build.Module,
    name: []const u8,
    tests_mod: *std.Build.Module,
) *std.Build.Step.Compile {
    tests_mod.addImport("testz", testz_mod);
    return b.addExecutable(.{
        .name = name,
        .root_module = wrappedRootModule(b, target, optimize, testz_mod, tests_mod, name),
    });
}

fn wrappedRootModule(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    testz_mod: *std.Build.Module,
    tests_mod: *std.Build.Module,
    name: []const u8,
) *std.Build.Module {
    const files = b.addWriteFiles();
    const root = files.add(b.fmt("{s}_testz_root.zig", .{name}),
        \\const std = @import("std");
        \\const testz = @import("testz");
        \\const tests = @import("testz_tests");
        \\
        \\pub const panic = if (@hasDecl(tests, "panic")) tests.panic else testz.panic;
        \\pub const std_options: std.Options = if (@hasDecl(tests, "std_options")) tests.std_options else .{};
        \\
        \\pub fn main(init: std.process.Init) !void {
        \\    const main_info = @typeInfo(@TypeOf(tests.main)).@"fn";
        \\    if (main_info.param_types.len > 1) {
        \\        @compileError("testz root wrapper supports tests.main() or tests.main(std.process.Init)");
        \\    }
        \\    const Return = main_info.return_type orelse
        \\        @compileError("testz root wrapper does not support noreturn tests.main");
        \\    if (main_info.param_types.len == 0) {
        \\        switch (@typeInfo(Return)) {
        \\            .error_union => try tests.main(),
        \\            .void => tests.main(),
        \\            else => @compileError("testz root wrapper supports tests.main returning void or !void"),
        \\        }
        \\    } else {
        \\        switch (@typeInfo(Return)) {
        \\            .error_union => try tests.main(init),
        \\            .void => tests.main(init),
        \\            else => @compileError("testz root wrapper supports tests.main returning void or !void"),
        \\        }
        \\    }
        \\}
        \\
    );

    const root_mod = b.createModule(.{
        .root_source_file = root,
        .target = target,
        .optimize = optimize,
    });
    root_mod.addImport("testz", testz_mod);
    root_mod.addImport("testz_tests", tests_mod);
    return root_mod;
}
