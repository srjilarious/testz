const std = @import("std");
const testz = @import("testz");
const TestFuncInfo = testz.TestFuncInfo;
const TestContext = testz.TestContext;
const Printer = testz.Printer;

pub fn runInternal(func: TestFuncInfo, expectedOutput: []const u8, opts: struct {
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
    _ = expectedOutput;
    // try testz.expectEqualStr(printer.array.array.items, expectedOutput);
}
