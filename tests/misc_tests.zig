const std = @import("std");
const testz = @import("testz");

const runInternal = @import("./utils.zig").runInternal;

fn allowNonTestzErrorsInternal() !void {
    const mem = try std.heap.page_allocator.alloc(u8, 10);
    defer std.heap.page_allocator.free(mem);
    try testz.expectEqual(true, true);
}

pub fn allowNonTestzErrors() !void {
    const expected: []const u8 =
        \\
        \\⋅
        \\
        \\1 Passed, 0 Failed, 0 Skipped, 1 Total Tests ( XX.XX ms)
        \\
    ;

    try runInternal(.{
        .func = allowNonTestzErrorsInternal,
        .name = "allowNonTestzErrors",
        .group = .{ .name = "Default", .tag = "default" },
    }, expected, .{});
}

fn alwaysFailTestInternal() !void {
    try testz.fail();
}

pub fn alwaysFailTest() !void {
    const expected: []const u8 =
        \\
        \\X
        \\FAIL alwaysFailTest: Test hit failure point.
        \\
        \\0 Passed, 1 Failed, 0 Skipped, 1 Total Tests ( XX.XX ms)
        \\
    ;

    try runInternal(.{
        .func = alwaysFailTestInternal,
        .name = "alwaysFailTest",
        .group = .{ .name = "Default", .tag = "default" },
    }, expected, .{});
}

fn successTestInternal() !void {
    try testz.expectEqual(12, 12);
    try testz.expectEqualStr("hello", "hello");
    try testz.expectNotEqual(10, 20);
    try testz.expectNotEqualStr("hello", "world");
    try testz.expectTrue(true);
    try testz.expectFalse(false);
}

pub fn successTest() !void {
    const expected: []const u8 =
        \\
        \\⋅
        \\
        \\1 Passed, 0 Failed, 0 Skipped, 1 Total Tests ( XX.XX ms)
        \\
    ;

    try runInternal(.{
        .func = successTestInternal,
        .name = "successTest",
        .group = .{ .name = "Default", .tag = "default" },
    }, expected, .{});
}

fn skip_notReadyTestInternal() !void {
    // nothing to see here.
}

pub fn testSkipNotReady() !void {
    const expected: []const u8 =
        \\
        \\↷
        \\
        \\0 Passed, 0 Failed, 1 Skipped, 1 Total Tests ( XX.XX ms)
        \\
    ;

    try runInternal(.{
        .func = skip_notReadyTestInternal,
        .name = "skip_notReadyTest",
        .group = .{ .name = "Default", .tag = "default" },
        .skip = true,
    }, expected, .{});
}
