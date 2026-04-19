const std = @import("std");
const builtin = @import("builtin");

const print = @import("./lib/printer.zig");
pub const Printer = print.Printer;
const Style = print.Style;
const Color = print.Color;

const core = @import("./core.zig");
pub const TestFunc = core.TestFunc;
pub const TestFuncInfo = core.TestFuncInfo;
const TestGroup = core.TestGroup;
pub const Group = core.Group;
pub const GroupList = core.GroupList;
pub const TestGroupInfo = core.TestGroupInfo;
const TestFuncGroup = core.TestFuncGroup;
const TestFuncMap = core.TestFuncMap;

pub const TestContext = @import("./context__testz.zig").TestContext;

const discovery = @import("./discovery.zig");
pub const discoverTests = discovery.discoverTests;

const capture_mod = @import("./capture.zig");
pub const OutputCapture = capture_mod.OutputCapture;
pub const CapturedOutput = capture_mod.CapturedOutput;

const DarkGray = "\x1b[90m";
const Red = "\x1b[91m";
const DarkGreen = "\x1b[32m";
const Green = "\x1b[92m";
const Blue = "\x1b[94m";
const Cyan = "\x1b[96m";
const Yellow = "\x1b[93m";
const White = "\x1b[97m";

const Reset = "\x1b[0m";

pub const RunTestOpts = struct {
    alloc: ?std.mem.Allocator = null,
    allowFilters: ?[]const []const u8 = null,
    verbose: bool = false,
    printStackTraceOnFail: bool = true,
    printColor: ?bool = null,
    // Used for internal testing putting XX.X ms as the time for each test.
    dummyTiming: bool = false,
    writer: ?Printer = null,
    testContext: ?*TestContext = null,
    /// Capture stdout/stderr written during each test at the OS fd level.
    /// Captured output from failing tests is shown in the failure section.
    /// Captured output from passing tests is only shown when printAllOutput is true.
    captureOutput: bool = false,
    /// When captureOutput is true, print captured output for all tests inline,
    /// not just failures.
    printAllOutput: bool = false,
};

pub const InfoOpts = struct {
    alloc: ?std.mem.Allocator = null,
    // verbose: bool = false,
    writer: ?Printer = null,
};

var GlobalTestContext: ?*TestContext = null;
var TestContexts: ?std.ArrayList(*TestContext) = null;

pub fn pushTestContext(context: *TestContext, opts: struct { alloc: ?std.mem.Allocator = null }) !void {
    var alloc: std.mem.Allocator = undefined;
    if (opts.alloc != null) {
        alloc = opts.alloc.?;
    } else {
        alloc = std.heap.page_allocator;
    }

    if (TestContexts == null) {
        TestContexts = .empty; //std.ArrayList(*TestContext).init(alloc);
    }

    if (GlobalTestContext == null) {
        GlobalTestContext = context;
    } else {
        // Push the current Global TestContext onto our stack.
        try TestContexts.?.append(alloc, GlobalTestContext.?);
        GlobalTestContext = context;
    }
}

pub fn popTestContext() void {
    if (TestContexts != null and TestContexts.?.items.len > 0) {
        GlobalTestContext = TestContexts.?.pop();
    } else {
        GlobalTestContext = null;
    }
}

pub fn fail() !void {
    try GlobalTestContext.?.fail();
}

pub fn failWith(err: anytype) !void {
    try GlobalTestContext.?.failWith(err);
}

pub fn expectTrue(actual: anytype) !void {
    try GlobalTestContext.?.expectTrue(actual);
}

pub fn expectFalse(actual: anytype) !void {
    try GlobalTestContext.?.expectFalse(actual);
}

pub fn expectEqualStr(actual: []const u8, expected: []const u8) !void {
    try GlobalTestContext.?.expectEqualStr(actual, expected);
}

pub fn expectEqual(actual: anytype, expected: anytype) !void {
    try GlobalTestContext.?.expectEqual(actual, expected);
}

pub fn expectEqualT(comptime T: type, actual: T, expected: T) !void {
    try GlobalTestContext.?.expectEqual(actual, expected);
}

pub fn expectNotEqualStr(actual: []const u8, expected: []const u8) !void {
    try GlobalTestContext.?.expectNotEqualStr(actual, expected);
}

pub fn expectNotEqual(actual: anytype, expected: anytype) !void {
    try GlobalTestContext.?.expectNotEqual(actual, expected);
}

pub fn expectError(actual: anytype, expected: anytype) !void {
    try GlobalTestContext.?.expectError(actual, expected);
}

fn printChars(writer: *Printer, ch: []const u8, num: usize) !void {
    var n = num;
    while (n > 0) {
        try writer.print("{s}", .{ch});
        n -= 1;
    }
}

fn printTestTime(
    writer: *Printer,
    timeNs: u64,
    opts: struct {
        printColor: bool,
        dummyTiming: bool = false,
    },
) !void {
    try writer.print(" (", .{});
    if (opts.printColor) try writer.print(White, .{});

    const timeNsFloat: f64 = @floatFromInt(timeNs);

    // Used for internal testing.
    if (opts.dummyTiming) {
        try writer.print(" XX.XX ms", .{});
    }
    // Seconds
    else if (timeNs > 1000_000_000) {
        try writer.print("{d: >6.2} secs", .{timeNsFloat / 1000_000_000.0});
    }
    // milliseconds
    else if (timeNs > 1000_000) {
        try writer.print("{d: >6.2} ms", .{timeNsFloat / 1000_000.0});
    }
    // microseconds
    else if (timeNs > 1000) {
        try writer.print("{d: >6.2} \u{03bc}s", .{timeNsFloat / 1000.0});
    }
    // nanoseconds.
    else {
        try writer.print("{d: >6} ns", .{timeNs});
    }

    if (opts.printColor) try writer.print(Reset, .{});
    try writer.print(")", .{});
}

fn printGroupSeparatorLine(writer: *Printer, maxTestNameLength: usize, printColor: bool) !void {
    // Print top line of group banner, 21 is the num of chars in a verbose test print
    // regardless of name length.
    if (printColor) try writer.print(DarkGreen, .{});

    try writer.print("# ", .{});
    try printChars(writer, "-", maxTestNameLength + 24 - 2);

    if (printColor) try writer.print(Reset, .{});
    //
}

/// Looks at the slice of tests and returns an owned slice of TestGroupInfo,
/// each entry holding the group name/tag and an owned slice of the test names
/// in that group (in the order they appear in `tests`).
/// The caller must free each `TestGroupInfo.tests` slice and the returned slice
/// itself using the same allocator (default: page_allocator).
pub fn getGroupList(tests: []const TestFuncInfo, opts: InfoOpts) ![]TestGroupInfo {
    const alloc = opts.alloc orelse std.heap.page_allocator;

    // tag -> index into groupList, so we can append test names in one pass.
    var tagToIdx = std.StringHashMap(usize).init(alloc);
    defer tagToIdx.deinit();

    var groupList: std.ArrayList(TestGroupInfo) = .empty;
    // testNameBuilders is parallel to groupList; entries are moved into groupList at the end.
    var testNameBuilders: std.ArrayList(std.ArrayList([]const u8)) = .empty;
    defer {
        // Free any builders not yet converted (only reached on error paths).
        for (testNameBuilders.items) |*b| b.deinit(alloc);
        testNameBuilders.deinit(alloc);
    }

    for (tests) |t| {
        const gop = try tagToIdx.getOrPut(t.group.tag);
        if (!gop.found_existing) {
            gop.value_ptr.* = groupList.items.len;
            try groupList.append(alloc, .{ .name = t.group.name, .tag = t.group.tag, .tests = &.{} });
            try testNameBuilders.append(alloc, .empty);
        }
        try testNameBuilders.items[gop.value_ptr.*].append(alloc, t.name);
    }

    // Transfer ownership of each name list into the corresponding TestGroupInfo.
    for (groupList.items, testNameBuilders.items) |*g, *b| {
        g.tests = try b.toOwnedSlice(alloc);
    }

    return groupList.toOwnedSlice(alloc);
}

fn pushGivenContext(givenContext: *TestContext, alloc: std.mem.Allocator, opts: RunTestOpts) !void {
    givenContext.verbose = opts.verbose;
    givenContext.printStackTraceOnFail = opts.printStackTraceOnFail;
    // givenContext.printColor = opts.printColor;
    try pushTestContext(givenContext, .{ .alloc = alloc });
}

// Checks if a test name is marked as skip.
fn startsWithSkip(name: []const u8) bool {
    return name.len >= 5 and std.mem.eql(u8, name[0..5], "skip_");
}

fn printCapturedOutput(writer: *Printer, stdout: []const u8, stderr: []const u8, printColor: bool) !void {
    if (stdout.len > 0) {
        const trimmed = std.mem.trimEnd(u8, stdout, "\r\n");
        if (trimmed.len > 0) {
            if (printColor) try writer.print(DarkGray, .{});
            try writer.print("\n  [stdout] ", .{});
            if (printColor) try writer.print(Reset, .{});
            try writer.print("{s}", .{trimmed});
        }
    }
    if (stderr.len > 0) {
        const trimmed = std.mem.trimEnd(u8, stderr, "\r\n");
        if (trimmed.len > 0) {
            if (printColor) try writer.print(DarkGray, .{});
            try writer.print("\n  [stderr] ", .{});
            if (printColor) try writer.print(Reset, .{});
            try writer.print("{s}", .{trimmed});
        }
    }
}

fn printMarkAndTime(
    errorCaught: bool,
    testsPassed: *u32,
    testStartTime: std.Io.Timestamp,
    writer: *Printer,
    printColor: bool,
    opts: RunTestOpts,
) !u64 {
    // If we passed, print a dot in non-verbose mode and a check-mark in verbose.
    if (!errorCaught) {
        testsPassed.* += 1;

        if (printColor) try writer.print(Green, .{});

        if (opts.verbose) {
            try writer.print("\u{2713}", .{});
        } else {
            try writer.print("\u{22c5}", .{});
        }

        if (printColor) try writer.print(Reset, .{});
    }

    const testEndTime = std.Io.Timestamp.now(std.Io.Threaded.global_single_threaded.io(), .awake);
    const testAmountNs: u64 = @intCast(testStartTime.durationTo(testEndTime).nanoseconds);

    if (opts.verbose) {
        try printTestTime(writer, testAmountNs, .{
            .printColor = printColor,
            .dummyTiming = opts.dummyTiming,
        });
    }

    return testAmountNs;
}

/// Takes a slice of TestFuncInfo and runs them using the given options
/// to handle filtering and how to display the results.
pub fn runTests(tests: []const TestFuncInfo, opts: RunTestOpts) !bool {
    var alloc: std.mem.Allocator = undefined;
    if (opts.alloc != null) {
        alloc = opts.alloc.?;
    } else {
        alloc = std.heap.page_allocator;
    }

    // Handle a potential passed in test context to use and
    // create a global context if one doesn't exist already.
    var createdOwnContext: bool = false;
    if (GlobalTestContext == null) {
        if (opts.testContext != null) {
            try pushGivenContext(opts.testContext.?, alloc, opts);
        } else {
            // Create a global context by pushing one, we'll clean this up at
            // the end of runTests.
            const newContext = try alloc.create(TestContext);

            newContext.* = TestContext.init(alloc, .{
                .verbose = opts.verbose,
                .printStackTraceOnFail = opts.printStackTraceOnFail,
            });
            try pushTestContext(newContext, .{ .alloc = alloc });
            createdOwnContext = true;
        }
    } else {
        if (opts.testContext != null) {
            try pushGivenContext(opts.testContext.?, alloc, opts);
        }
    }

    var writer: Printer = undefined;
    var usingDefaultWriter: bool = false;
    if (opts.writer != null) {
        writer = opts.writer.?;
    } else {
        writer = try Printer.stdout(alloc);
        usingDefaultWriter = true;
    }

    var printColor: bool = writer.supportsColor();
    if (opts.printColor != null) {
        printColor = printColor and opts.printColor.?;
    }
    GlobalTestContext.?.printColor = printColor;

    // Filter on the list of tests based on provided tag filters.
    var testsToRun: []const TestFuncInfo = undefined;
    if (opts.allowFilters != null) {
        var filters = std.StringHashMap(bool).init(alloc);
        defer filters.deinit();
        for (opts.allowFilters.?) |filt| {
            try filters.put(filt, true);
        }

        var tempList: std.ArrayList(TestFuncInfo) = .empty;
        for (tests) |t| {
            var added: bool = false;
            if (filters.contains(t.group.tag)) {
                try tempList.append(alloc, t);
                added = true;
            }

            if (!added) {
                if (filters.contains(t.name)) {
                    try tempList.append(alloc, t);
                }
            }
        }

        testsToRun = try tempList.toOwnedSlice(alloc);
    } else {
        testsToRun = tests;
    }

    // Create a map of tags to the list of tests within that group from
    // the potentially filtered set.
    var groupMap = TestFuncMap.init(alloc);
    defer groupMap.deinit();

    for (testsToRun) |t| {
        if (!groupMap.contains(t.group.tag)) {
            const group = TestFuncGroup.init(t.group.name.?, alloc);
            try groupMap.put(t.group.tag, group);
        }

        var group = groupMap.getPtr(t.group.tag).?;
        try group.tests.append(alloc, t);
    }

    try writer.print("\n", .{});

    var testsRun: u32 = 0;
    var testsPassed: u32 = 0;
    var testsFailed: u32 = 0;
    var testsSkipped: u32 = 0;
    var totalTestTimeNs: u64 = 0;

    // Find the longest length name in the tests for formatting.
    var verboseLength: usize = 0;
    // if (opts.verbose) {
    for (testsToRun) |f| {
        if (f.name.len > verboseLength) {
            verboseLength = f.name.len;
        }
    }
    // }

    // Iterate over each group of tests.
    var groupIterator = groupMap.keyIterator();
    while (true) {
        const groupTag = groupIterator.next();
        if (groupTag == null) break;

        var group = groupMap.get(groupTag.?.*).?;

        // Clean up the group test memory once done iterating
        defer group.deinit();

        // Print out the name of the current group unless it's the default one.
        if (opts.verbose and group.name.len > 0 and !std.mem.eql(u8, groupTag.?.*, "default")) {
            try printGroupSeparatorLine(&writer, verboseLength, printColor);

            try writer.print("\n", .{});
            if (printColor) try writer.print(DarkGreen, .{});
            try writer.print("# ", .{});

            if (printColor) try writer.print(Green, .{});
            try writer.print("{s}\n", .{group.name});

            try printGroupSeparatorLine(&writer, verboseLength, printColor);
            try writer.flush();
        }

        // Run each of the tests for the group.
        for (group.tests.items) |f| {
            const testStartTime = std.Io.Timestamp.now(std.Io.Threaded.global_single_threaded.io(), .awake);

            testsRun += 1;

            const skip = startsWithSkip(f.name);
            const testPrintName = if (skip) f.name[5..] else f.name;

            GlobalTestContext.?.setCurrentTest(testPrintName);
            if (opts.verbose) {
                if (skip) {
                    try writer.print("\nSkipping ", .{});
                    if (printColor) try writer.print(DarkGray, .{});
                    try writer.print("{s}", .{testPrintName});
                    if (printColor) try writer.print(Reset, .{});
                    try writer.print("..", .{});
                } else {
                    try writer.print("\nRunning ", .{});
                    if (printColor) try writer.print(White, .{});
                    try writer.print("{s}", .{testPrintName});
                    if (printColor) try writer.print(Reset, .{});
                    try writer.print("...", .{});
                }
                const num = @min(verboseLength - testPrintName.len, 128);
                try printChars(&writer, ".", num);
            }

            // If we are skipping this test, print a jump over arrow.
            if (skip) {
                if (printColor) try writer.print(Yellow, .{});
                try writer.print("\u{21b7}", .{});
                if (printColor) try writer.print(Reset, .{});
                testsSkipped += 1;
                continue;
            }

            // Flush before redirecting fds so framework output already in the
            // buffer reaches the real stdout, not the capture pipe.
            if (opts.captureOutput) try writer.flush();

            var cap: capture_mod.OutputCapture = undefined;
            if (opts.captureOutput) {
                cap = try capture_mod.OutputCapture.begin();
            }

            var errorCaught = false;
            switch (f.func) {
                .basic => |basicFn| basicFn() catch {
                    if (printColor) try writer.print(Red, .{});
                    try writer.print("X", .{});
                    if (printColor) try writer.print(Reset, .{});
                    errorCaught = true;
                    testsFailed += 1;
                },
                .full => |fullFn| {
                    var dAlloc = std.heap.DebugAllocator(.{}){};
                    const testAlloc = dAlloc.allocator();
                    const testIo = std.Io.Threaded.global_single_threaded.io();
                    fullFn(testIo, testAlloc) catch {
                        if (printColor) try writer.print(Red, .{});
                        try writer.print("X", .{});
                        if (printColor) try writer.print(Reset, .{});
                        errorCaught = true;
                        testsFailed += 1;
                    };
                    const leakCheck = dAlloc.deinit();
                    if (!errorCaught and leakCheck == .leak) {
                        var leakFailure = try core.TestFailure.init(testPrintName, alloc);
                        leakFailure.errorMessage = try alloc.dupe(u8, "Memory leak detected");
                        try GlobalTestContext.?.failures.append(alloc, leakFailure);
                        if (printColor) try writer.print(Red, .{});
                        try writer.print("X", .{});
                        if (printColor) try writer.print(Reset, .{});
                        errorCaught = true;
                        testsFailed += 1;
                    }
                },
            }

            // End capture and route output to the right place.
            if (opts.captureOutput) {
                const captured = try cap.end(alloc);

                var stdout_transferred = false;
                var stderr_transferred = false;

                if (errorCaught) {
                    // Attach captured output to the TestFailure record for this
                    // test so it appears in the failure summary at the end.
                    const fail_items = GlobalTestContext.?.failures.items;
                    if (fail_items.len > 0) {
                        const last = &fail_items[fail_items.len - 1];
                        if (std.mem.eql(u8, last.testName, testPrintName)) {
                            if (captured.stdout.len > 0) {
                                last.capturedStdout = captured.stdout;
                                stdout_transferred = true;
                            }
                            if (captured.stderr.len > 0) {
                                last.capturedStderr = captured.stderr;
                                stderr_transferred = true;
                            }
                        }
                    }
                }

                totalTestTimeNs += try printMarkAndTime(errorCaught, &testsPassed, testStartTime, &writer, printColor, opts);

                // Show captured output inline when printAllOutput is set (passing tests),
                // or for failing tests that had no TestFailure record (raw error).
                const showInline = (opts.printAllOutput and !errorCaught) or
                    (errorCaught and !stdout_transferred and !stderr_transferred);
                if (showInline) {
                    try printCapturedOutput(&writer, captured.stdout, captured.stderr, printColor);
                }

                // Free any slices that weren't transferred to a TestFailure.
                if (!stdout_transferred) alloc.free(captured.stdout);
                if (!stderr_transferred) alloc.free(captured.stderr);
            } else {
                // Just print the mark and time if not capturing output.
                totalTestTimeNs += try printMarkAndTime(errorCaught, &testsPassed, testStartTime, &writer, printColor, opts);
            }

            try writer.flush();
        }

        if (opts.verbose and group.name.len > 0) {
            try writer.print("\n\n", .{});
        }
    }

    for (GlobalTestContext.?.failures.items) |failure| {
        if (printColor) {
            try writer.print("\n" ++ Red ++ "FAIL " ++ Yellow ++ "{s}" ++ Reset, .{failure.testName});
        } else {
            try writer.print("\nFAIL {s}", .{failure.testName});
        }
        try writer.print(": {?s}", .{failure.errorMessage});
        if (failure.capturedStdout != null or failure.capturedStderr != null) {
            try printCapturedOutput(
                &writer,
                failure.capturedStdout orelse "",
                failure.capturedStderr orelse "",
                printColor,
            );
        }
        if (opts.printStackTraceOnFail) {
            if (failure.stackTrace != null) {
                try writer.print("{?s}\n", .{failure.stackTrace});
            } else {
                try writer.print("\nNo stack trace available.\n", .{});
            }
        }
    }

    if (printColor) {
        try writer.print("\n\n" ++ White ++ "{} " ++ Green ++ "Passed" ++ Reset ++ ", " ++
            White ++ "{} " ++ Red ++ "Failed" ++ Reset ++ ", " ++
            White ++ "{} " ++ Yellow ++ "Skipped" ++ Reset ++ ", " ++
            White ++ "{} " ++ Cyan ++ "Total Tests" ++ Reset, //"({})"\n\n",
            .{ testsPassed, testsFailed, testsSkipped, testsRun });
    } else {
        try writer.print("\n\n{} Passed, {} Failed, {} Skipped, {} Total Tests", .{ testsPassed, testsFailed, testsSkipped, testsRun });
    }

    try printTestTime(&writer, totalTestTimeNs, .{
        .printColor = printColor,
        .dummyTiming = opts.dummyTiming,
    });
    try writer.print("\n", .{});
    try writer.flush();

    // Clean up the slice we created if we had filters.
    if (opts.allowFilters != null) {
        alloc.free(testsToRun);
    }

    if (usingDefaultWriter) {
        writer.deinit();
    }

    if (createdOwnContext) {
        const gtcAlloc = GlobalTestContext.?.alloc;
        GlobalTestContext.?.deinit();
        gtcAlloc.destroy(GlobalTestContext.?);
        popTestContext();
    }

    if (opts.testContext != null) {
        popTestContext();
    }

    return testsFailed == 0;
}

// Vendored argument parsing lib.
const zargs = @import("lib/zargunaught.zig");
const Option = zargs.Option;

const GroupTitleStyle: Style = .{ .fg = Color.BrightGreen, .bg = Color.Reset, .mod = .{ .underline = true, .bold = true } };

const GroupNameStyle: Style = .{ .fg = Color.BrightWhite, .bg = Color.Reset, .mod = .{ .bold = true } };

const GroupTagStyle: Style = .{ .fg = Color.BrightYellow, .bg = Color.Reset, .mod = .{} };

/// A default test runner implementation that parses the command line for options and runs the passed in tests.
/// It allows for verbose/non-verbose output, disabling printing stack traces and providing a list of
/// filter tags to only run some tests.
pub fn testzRunner(testsToRun: []const TestFuncInfo, process_args: std.process.Args) !void {
    var parser = try zargs.ArgParser.init(
        std.heap.page_allocator,
        .{
            .name = "Unit tests",
            .description = "Unit tests....",
            .opts = &[_]Option{
                Option{
                    .longName = "verbose",
                    .shortName = "v",
                    .description = "Verbose output",
                    .maxNumParams = 0,
                },
                Option{
                    .longName = "stack_trace",
                    .shortName = "s",
                    .description = "Print stack traces on errors",
                    .maxNumParams = 0,
                    .default = zargs.DefaultValue.set(),
                },
                Option{
                    .longName = "groups",
                    .shortName = "g",
                    .description = "Lists the groups of tests",
                    .maxNumParams = 0,
                },
                Option{
                    .longName = "color",
                    .description = "Forces color output",
                    .maxNumParams = 0,
                    .default = zargs.DefaultValue.set(),
                },
                Option{
                    .longName = "capture",
                    .shortName = "c",
                    .description = "Capture stdout/stderr per test; show on failure",
                    .maxNumParams = 0,
                    .default = zargs.DefaultValue.set(),
                },
                Option{
                    .longName = "print-output",
                    .shortName = "p",
                    .description = "Print all captured output inline, not just on failures",
                    .maxNumParams = 0,
                },
                Option{
                    .longName = "help",
                    .shortName = "h",
                    .description = "Prints out the help text.",
                },
            },
        },
    );
    defer parser.deinit();

    var args = parser.parse(process_args) catch |err| {
        std.debug.print("Error parsing args: {any}\n", .{err});
        return;
    };
    defer args.deinit();

    const optPrintColor: ?bool = args.hasOption("color");

    const windows_cp = if (builtin.os.tag == .windows) struct {
        extern "kernel32" fn GetConsoleOutputCP() callconv(.winapi) std.os.windows.UINT;
        extern "kernel32" fn SetConsoleOutputCP(wCodePageID: std.os.windows.UINT) callconv(.winapi) std.os.windows.BOOL;
    } else struct {};
    const orig_windows_cp = if (builtin.os.tag == .windows) windows_cp.GetConsoleOutputCP() else 0;
    defer {
        if (builtin.os.tag == .windows) _ = windows_cp.SetConsoleOutputCP(orig_windows_cp);
    }

    // Set the code page to UTF-8 on Windows so we can print unicode characters.  The code
    // above restores the original code page on exit.
    if (builtin.os.tag == .windows) {
        _ = windows_cp.SetConsoleOutputCP(65001); // UTF-8 code page
    }

    var printer = try Printer.stdout(std.heap.page_allocator);
    defer printer.deinit();

    // Prints out the help text and exits
    if (args.hasOption("help")) {
        // using duped Printer struct comes from using vendored zargunaught lib

        var help = try zargs.help.HelpFormatter.init(&parser, printer, zargs.help.DefaultTheme, std.heap.page_allocator);
        help.printHelpText() catch |err| {
            std.debug.print("Err: {any}\n", .{err});
        };
        try printer.flush();
    }
    // List out the available group tags and names.
    else if (args.hasOption("groups")) {
        const verbose = args.hasOption("verbose");
        const groups = try getGroupList(testsToRun, .{});
        defer {
            for (groups) |g| std.heap.page_allocator.free(g.tests);
            std.heap.page_allocator.free(groups);
        }

        if (groups.len > 0) {
            if (!args.hasOption("color")) {
                try printer.print("Test groups:\n\n", .{});
                for (groups) |g| {
                    try printer.print("{?s}: tag='{s}'.\n", .{ g.name, g.tag });
                    if (verbose) {
                        for (g.tests) |testName| {
                            try printer.print("  - {s}\n", .{testName});
                        }
                        try printer.print("\n", .{});
                    }
                }

                try printer.print("\n\nUse the tag names as arguments to the test program to run that group.  Multiple group tags can be included.\n", .{});
            } else {
                try GroupTitleStyle.set(printer);
                try printer.print("Test groups", .{});
                try Style.reset(printer);
                try printer.print(":\n\n", .{});

                for (groups) |g| {
                    try GroupNameStyle.set(printer);
                    try printer.print("{?s}", .{g.name});
                    try Style.reset(printer);

                    try printer.print(": tag=", .{});

                    try GroupTagStyle.set(printer);
                    try printer.print("'{s}'", .{g.tag});
                    try Style.reset(printer);

                    try printer.print(".\n", .{});

                    if (verbose) {
                        for (g.tests) |testName| {
                            try printer.print(DarkGray, .{});
                            try printer.print("  - {s}", .{testName});
                            try printer.print(Reset, .{});
                            try printer.print("\n", .{});
                        }
                        try printer.print("\n", .{});
                    }
                }

                try printer.print("\n\nUse the tag names as arguments to the test program to run that group.  Multiple group tags can be included.\n", .{});
            }
        } else {
            try printer.print("No test groups found!\n", .{});
        }

        try printer.flush();
    }
    // Run the tests in this case.
    else {
        const verbose = args.hasOption("verbose");
        const optPrintStackTrace = args.hasOption("stack_trace");
        const captureOutput = args.hasOption("capture");
        const printAllOutput = args.hasOption("print-output");

        const filters = (if (args.positional.items.len > 0) blk: {
            break :blk args.positional.items;
        } else null);

        _ = try runTests(testsToRun, .{
            .verbose = verbose,
            .allowFilters = filters,
            .printStackTraceOnFail = optPrintStackTrace,
            .printColor = optPrintColor,
            .captureOutput = captureOutput,
            .printAllOutput = printAllOutput,
        });
    }
}
