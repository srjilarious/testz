const std = @import("std");
const testz = @import("testz");
const TestFuncInfo = testz.TestFuncInfo;
const TestContext = testz.TestContext;
const Printer = testz.Printer;

const runInternal = @import("./utils.zig").runInternal;

fn expectEqualFailTestInternal() !void {
    try testz.expectEqual(10, 20);
}

pub fn expectEqualFailTest() !void {
    const expected: []const u8 =
        \\
        \\X
        \\FAIL expectEqualFailTest: Expected 20 to be 10
        \\
        \\0 Passed, 1 Failed, 0 Skipped, 1 Total Tests ( XX.XX ms)
        \\
    ;

    try runInternal(.{
        .func = expectEqualFailTestInternal,
        .name = "expectEqualFailTest",
        .group = .{ .name = "Default", .tag = "default" },
    }, expected, .{});
}

fn expectNotEqualFailTestInternal() !void {
    try testz.expectNotEqual(10, 10);
}

pub fn expectNotEqualFailTest() !void {
    const expected: []const u8 =
        \\
        \\X
        \\FAIL expectNotEqualFailTest: Expected 10 to NOT be 10
        \\
        \\0 Passed, 1 Failed, 0 Skipped, 1 Total Tests ( XX.XX ms)
        \\
    ;

    try runInternal(.{
        .func = expectNotEqualFailTestInternal,
        .name = "expectNotEqualFailTest",
        .group = .{ .name = "Default", .tag = "default" },
    }, expected, .{});
}

fn expectEqualStrFailTestInternal() !void {
    try testz.expectEqualStr("hello", "world");
}

pub fn expectEqualStrFailTest() !void {
    const expected: []const u8 =
        \\
        \\X
        \\FAIL expectEqualStrFailTest: Expected "world" to be "hello". Differs at index 0, expected="h", actual="w"
        \\
        \\0 Passed, 1 Failed, 0 Skipped, 1 Total Tests ( XX.XX ms)
        \\
    ;

    try runInternal(.{
        .func = expectEqualStrFailTestInternal,
        .name = "expectEqualStrFailTest",
        .group = .{ .name = "Default", .tag = "default" },
    }, expected, .{});
}

fn expectNotEqualStrFailTestInternal() !void {
    try testz.expectNotEqualStr("hello", "hello");
}

pub fn expectNotEqualStrFailTest() !void {
    const expected: []const u8 =
        \\
        \\X
        \\FAIL expectNotEqualStrFailTest: Expected hello to NOT be hello
        \\
        \\0 Passed, 1 Failed, 0 Skipped, 1 Total Tests ( XX.XX ms)
        \\
    ;

    try runInternal(.{
        .func = expectNotEqualStrFailTestInternal,
        .name = "expectNotEqualStrFailTest",
        .group = .{ .name = "Default", .tag = "default" },
    }, expected, .{});
}

fn expectTrueFailTestInternal() !void {
    try testz.expectTrue(false);
}

pub fn expectTrueFailTest() !void {
    const expected: []const u8 =
        \\
        \\X
        \\FAIL expectTrueFailTest: Expected false to be true
        \\
        \\0 Passed, 1 Failed, 0 Skipped, 1 Total Tests ( XX.XX ms)
        \\
    ;

    try runInternal(.{
        .func = expectTrueFailTestInternal,
        .name = "expectTrueFailTest",
        .group = .{ .name = "Default", .tag = "default" },
    }, expected, .{});
}

fn expectFalseFailTestInternal() !void {
    try testz.expectFalse(true);
}

pub fn expectFalseFailTest() !void {
    const expected: []const u8 =
        \\
        \\X
        \\FAIL expectFalseFailTest: Expected true to be false
        \\
        \\0 Passed, 1 Failed, 0 Skipped, 1 Total Tests ( XX.XX ms)
        \\
    ;

    try runInternal(.{
        .func = expectFalseFailTestInternal,
        .name = "expectFalseFailTest",
        .group = .{ .name = "Default", .tag = "default" },
    }, expected, .{});
}
