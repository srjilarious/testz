const std = @import("std");
const testz = @import("testz");
const TestFuncInfo = testz.TestFuncInfo;
const TestContext = testz.TestContext;
const Printer = testz.Printer;

pub fn runInternal(func: TestFuncInfo, expectedOutput: []const u8, opts: struct {
    withColor: bool = false,
    verbose: bool = false,
}) !void {
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
        .verbose = opts.verbose,
    });

    // Check our test output.
    const result = printer.array.writer.written();
    try testz.expectEqualStr(result, expectedOutput);
}

pub fn runInternalMulti(tests: []const TestFuncInfo, expectedOutput: []const u8, opts: struct {
    verbose: bool = false,
    allowFilters: ?[]const []const u8 = null,
}) !void {
    var testContext = TestContext.init(std.heap.page_allocator, .{});
    defer testContext.deinit();

    var printer = try Printer.memory(std.heap.page_allocator);
    defer printer.deinit();

    _ = try testz.runTests(tests, .{
        .testContext = &testContext,
        .writer = printer,
        .printColor = false,
        .printStackTraceOnFail = false,
        .dummyTiming = true,
        .verbose = opts.verbose,
        .allowFilters = opts.allowFilters,
    });

    const result = printer.array.writer.written();
    try testz.expectEqualStr(result, expectedOutput);
}
