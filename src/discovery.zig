const std = @import("std");

const core = @import("./core.zig");
const TestFunc = core.TestFunc;
const TestFuncInfo = core.TestFuncInfo;
const TestGroup = core.TestGroup;
const Group = core.Group;
const TestFuncGroup = core.TestFuncGroup;
const TestFuncMap = core.TestFuncMap;

pub const DiscoverOpts = struct {
    // If set true, only public functions ending with `Test` are considered.
    testsEndWithTest: bool = false,

    // If true, will log at compile time all of the functions seen and the result
    // of how it is categorized.
    debugDiscovery: bool = false,
};

pub fn discoverTestsInModule(comptime groupInfo: TestGroup, comptime mod: type, opts: DiscoverOpts) []const TestFuncInfo {
    comptime var numTests: usize = 0;
    const decls = @typeInfo(mod).Struct.decls;
    inline for (decls) |decl| {
        const fld = @field(mod, decl.name);
        const ti = @typeInfo(@TypeOf(fld));
        if (ti == .Fn) {
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
        if (ti == .Fn) {
            if (opts.debugDiscovery) {
                @compileLog("Evaluating function:", decl.name);
            }

            var isTest: bool = true;
            if (opts.testsEndWithTest and !std.mem.endsWith(u8, decl.name, "Test")) {
                if (opts.debugDiscovery) {
                    @compileLog("Not running {} as a test since its name doesn't end with `Test`", .{decl.name});
                }

                isTest = false;
            }

            if (isTest) {
                const skip = std.mem.startsWith(u8, decl.name, "skip_");
                if (skip and opts.debugDiscovery) {
                    @compileLog("Function {} will be skipped since it starts with `_skip`", .{decl.name});
                }

                tests[idx] = .{
                    .func = fld,
                    .name = decl.name,
                    .skip = skip,
                    .group = groupInfo,
                };
                idx += 1;
            }
        }
    }

    const final = tests;
    return &final;
}

pub fn discoverTests(comptime mods: anytype, opts: DiscoverOpts) []const TestFuncInfo {
    const MaxTests = 10000;
    comptime var tests: [MaxTests]TestFuncInfo = undefined;
    comptime var totalTests: usize = 0;
    comptime var fieldIdx = 0;
    comptime var currGroup: TestGroup = undefined;
    const ModsType = @TypeOf(mods);
    const modsTypeInfo = @typeInfo(ModsType);
    if (modsTypeInfo != .Struct) {
        @compileError("expected tuple or struct argument of modules, found " ++ @typeName(ModsType));
    }

    const fieldsInfo = modsTypeInfo.Struct.fields;
    inline for (fieldsInfo) |_| {
        const fieldName = std.fmt.comptimePrint("{}", .{fieldIdx});
        const currIndexItem = @field(mods, fieldName);
        fieldIdx += 1;
        const currMod = blk: {
            if (@TypeOf(currIndexItem) == Group) {
                currGroup = .{
                    .name = @field(currIndexItem, "name"),
                    .tag = @field(currIndexItem, "tag"),
                };
                // Grab the mods field from the Group to extract actual tests from.
                break :blk @field(currIndexItem, "mod");
            } else {
                currGroup = .{
                    .name = "Default",
                    .tag = "default",
                };

                break :blk @field(mods, fieldName);
            }
        };

        const modTests = discoverTestsInModule(currGroup, currMod, opts);
        for (modTests) |t| {
            tests[totalTests] = t;
            totalTests += 1;
        }
    }

    const final: [totalTests]TestFuncInfo = tests[0..totalTests].*;
    return &final;
}
