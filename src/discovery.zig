const std = @import("std");

const core = @import("./core.zig");
const TestFunc = core.TestFunc;
const TestFuncInfo = core.TestFuncInfo;
const TestGroup = core.TestGroup;
const Group = core.Group;
const GroupList = core.GroupList;
const TestFuncGroup = core.TestFuncGroup;
const TestFuncMap = core.TestFuncMap;

pub const DiscoverOpts = struct {
    // If set true, only public functions ending with `Test` are considered.
    testsEndWithTest: bool = false,

    // If true, will log at compile time all of the functions seen and the result
    // of how it is categorized.
    debugDiscovery: bool = false,
};

// Replace std.mem.endsWith(u8, decl.name, "Test") with:
inline fn endsWithTest(comptime name: []const u8) bool {
    return name.len >= 4 and std.mem.eql(u8, name[name.len - 4 ..], "Test");
}

// Replace std.mem.startsWith(u8, decl.name, "skip_") with:
inline fn startsWithSkip(comptime name: []const u8) bool {
    return name.len >= 5 and std.mem.eql(u8, name[0..5], "skip_");
}

pub fn discoverTestsInModule(comptime groupInfo: TestGroup, comptime mod: type, opts: DiscoverOpts) []const TestFuncInfo {
    comptime var numTests: usize = 0;
    const decls = @typeInfo(mod).@"struct".decls;
    inline for (decls) |decl| {
        const fld = @field(mod, decl.name);
        const ti = @typeInfo(@TypeOf(fld));
        if (ti == .@"fn") {
            if (opts.testsEndWithTest and std.mem.endsWith(u8, decl.name, "Test")) {
                numTests += 1;
            } else {
                numTests += 1;
            }
        }
    }

    comptime var tests: [numTests]TestFuncInfo = undefined;
    comptime var idx: usize = 0;
    inline for (decls) |decl| {
        const fld = @field(mod, decl.name);
        const ti = @typeInfo(@TypeOf(fld));
        if (ti == .@"fn") {
            if (opts.debugDiscovery) {
                @compileLog("Evaluating function:", decl.name);
            }

            tests[idx] = .{
                .func = fld,
                .name = decl.name,
                .skip = false,
                .group = groupInfo,
            };
            idx += 1;

            // var isTest: bool = true;
            // if (opts.testsEndWithTest and !endsWithTest(decl.name)) {
            //     if (opts.debugDiscovery) {
            //         @compileLog("Not running {} as a test since its name doesn't end with `Test`", .{decl.name});
            //     }

            //     isTest = false;
            // }

            // if (isTest) {
            //     const skip = startsWithSkip(decl.name);
            //     if (skip and opts.debugDiscovery) {
            //         @compileLog("Function {} will be skipped since it starts with `_skip`", .{decl.name});
            //     }

            //     tests[idx] = .{
            //         .func = fld,
            //         .name = decl.name,
            //         .skip = skip,
            //         .group = groupInfo,
            //     };
            //     idx += 1;
            // }
        }
    }

    const final = tests;
    return &final;
}

fn addModuleTests(comptime tests: []TestFuncInfo, comptime mod: type, currGroup: TestGroup, opts: DiscoverOpts, idx: usize) usize {
    comptime var testIdx = idx;

    const modTests = discoverTestsInModule(currGroup, mod, opts);
    for (modTests) |t| {
        tests[testIdx] = t;
        testIdx += 1;
    }

    return testIdx;
}

pub fn discoverTests(comptime mods: anytype, opts: DiscoverOpts) []const TestFuncInfo {
    const MaxTests = 10000;
    comptime var tests: [MaxTests]TestFuncInfo = undefined;
    comptime var totalTests: usize = 0;
    // comptime var fieldIdx = 0;
    comptime var currGroup: TestGroup = undefined;
    const ModsType = @TypeOf(mods);
    const modsTypeInfo = @typeInfo(ModsType);
    if (modsTypeInfo != .@"struct") {
        @compileError("expected tuple or struct argument of modules, found " ++ @typeName(ModsType));
    }

    const fields = modsTypeInfo.@"struct".fields;
    inline for (fields, 0..) |field, i| {
        _ = i; // You can use i if needed for debugging
        const currIndexItem = @field(mods, field.name);

        if (@TypeOf(currIndexItem) == Group) {
            currGroup = .{
                .name = @field(currIndexItem, "name"),
                .tag = @field(currIndexItem, "tag"),
            };

            // Grab the mods field from the Group to extract actual tests from.
            const currMod = @field(currIndexItem, "mod");
            totalTests = addModuleTests(&tests, currMod, currGroup, opts, totalTests);
        } else if (@TypeOf(currIndexItem) == GroupList) {
            currGroup = .{
                .name = @field(currIndexItem, "name"),
                .tag = @field(currIndexItem, "tag"),
            };

            // Grab the mods field from the Group to extract actual tests from.
            const groupMods = @field(currIndexItem, "mods");
            const groupModType = @TypeOf(groupMods);
            const groupModTypeInfo = @typeInfo(groupModType);
            if (groupModTypeInfo == .pointer) {
                for (groupMods) |currMod| {
                    totalTests = addModuleTests(&tests, currMod, currGroup, opts, totalTests);
                }
            } else {
                @compileLog("Expected a slice of modules to discover tests from.  Instead got");
                @compileError(groupMods);
            }
            // else {
            // }
        } else {
            currGroup = .{
                .name = "Default",
                .tag = "default",
            };

            // We expect a normal struct/module import result in this case.
            totalTests = addModuleTests(&tests, @field(mods, field.name), currGroup, opts, totalTests);
        }
    }

    const final: [totalTests]TestFuncInfo = tests[0..totalTests].*;
    return &final;
}
