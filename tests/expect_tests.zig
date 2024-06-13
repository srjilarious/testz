const std = @import("std");
const testz = @import("testz");
const TestFuncInfo = testz.TestFuncInfo;
const TestContext = testz.TestContext;
const Printer = testz.Printer;

fn runInternal(func: TestFuncInfo) !void {
    // Create a test context with a buffer printer so we can check the output.
    var testContext = TestContext.init(std.heap.page_allocator, .{});
    defer testContext.deinit();

    // Create a memory printer so we can capture the test output.
    var printer = try Printer.memory(std.heap.page_allocator);
    defer printer.deinit();

    try testz.pushTestContext(&testContext, .{});
    _ = try testz.runTests(&.{func}, .{ .writer = printer });
    testz.popTestContext();

    // Check our test output.
    std.debug.print("Test output: {s}\n", .{printer.array.array.items});
}

fn expectEqualFailTestInternal() !void {
    try testz.expectEqual(10, 20);
}

pub fn expectEqualFailTest() !void {
    try runInternal(.{
        .func = expectEqualFailTestInternal,
        .name = "expectEqualFailTest",
        .group = .{ .name = "Default", .tag = "default" },
    });
}

// pub fn expectNotEqualFailTest() !void {
//     try testz.expectNotEqual(10, 10);
// }
//
// pub fn expectEqualStrFailTest() !void {
//     try testz.expectEqualStr("hello", "world");
// }
//
// pub fn expectNotEqualStrFailTest() !void {
//     try testz.expectNotEqualStr("hello", "hello");
// }
//
// pub fn expectTrueFailTest() !void {
//     try testz.expectTrue(false);
// }
//
// pub fn expectFalseFailTest() !void {
//     try testz.expectFalse(true);
// }
