const std = @import("std");
const testz = @import("testz");

fn allowNonTestzErrors() !void {
    const mem = try std.heap.page_allocator.alloc(u8, 10);
    defer std.heap.page_allocator.free(mem);
    try testz.expectEqual(true, true);
}

fn failTest_expectEqual() !void {
    try testz.expectEqual(10, 20);
}

fn failTest_expectNotEqual() !void {
    try testz.expectNotEqual(10, 10);
}

fn failTest_expectTrue() !void {
    try testz.expectTrue(false);
}

fn failTest_expectFalse() !void {
    try testz.expectFalse(true);
}

fn failTest_alwaysFail() !void {
    try testz.fail();
}

fn successTest() !void {
    try testz.expectEqual(true, true);
    try testz.expectNotEqual(10, 20);
    try testz.expectTrue(true);
    try testz.expectFalse(false);
}

fn skip_Test() !void {
    // nothing to see here.
}

pub fn main() !void {
    _ = testz.runTests(&[_]testz.TestFuncInfo{
        .{ .func = successTest, .name = "successTest", .skip = false },
        .{ .func = skip_Test, .name = "skip_Test", .skip = true },
        .{ .func = allowNonTestzErrors, .name = "allowNonTestzErrors", .skip = false },
        .{ .func = failTest_expectEqual, .name = "failTest_expectEqual", .skip = false },
        .{ .func = failTest_expectNotEqual, .name = "failTest_expectNotEqual", .skip = false },
        .{ .func = failTest_expectTrue, .name = "failTest_expectTrue", .skip = false },
        .{ .func = failTest_expectFalse, .name = "failTest_expectFalse", .skip = false },
        .{ .func = failTest_alwaysFail, .name = "failTest_alwaysFail", .skip = false },
    }, true);
}
