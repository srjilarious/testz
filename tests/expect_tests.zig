const std = @import("std");
const testz = @import("testz");
const TestFuncInfo = testz.TestFuncInfo;
const TestContext = testz.TestContext;
const Printer = testz.Printer;

fn runInternal(func: TestFuncInfo, expectedOutput: []const u8, opts: struct {
    withColor: bool = false,
}) !void {
    _ = opts;

    // Create a test context with a buffer printer so we can check the output.
    var testContext = TestContext.init(std.heap.page_allocator, .{});
    defer testContext.deinit();

    // Create a memory printer so we can capture the test output.
    var printer = try Printer.memory(std.heap.page_allocator);
    defer printer.deinit();

    _ = try testz.runTests(&.{func}, .{
        .testContext = &testContext,
        .writer = printer,
        .printColor = false, //opts.withColor,
        // Don't worry about validating stack traces since they are tied to the machine they run on.
        .printStackTraceOnFail = false,
        // Replaces the actual time with a dummy ( XX.XX ms) string instead
        .dummyTiming = true,
    });

    // Check our test output.
    try testz.expectEqualStr(expectedOutput, printer.array.array.items);
    // std.debug.print("Test output: {s}\n", .{printer.array.array.items});
}

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
