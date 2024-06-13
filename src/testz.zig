// zig fmt: off
const std = @import("std");


pub const Printer = @import("./printer.zig").Printer;

const core = @import("./core.zig");
pub const TestFunc = core.TestFunc;
pub const TestFuncInfo = core.TestFuncInfo;
const TestGroup = core.TestGroup;
pub const Group = core.Group;
const TestFuncGroup = core.TestFuncGroup;
const TestFuncMap = core.TestFuncMap;

pub const TestContext = @import("./context__testz.zig").TestContext;

const discovery = @import("./discovery.zig");
pub const discoverTests = discovery.discoverTests;

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
    printColor: bool = true,
    writer: ?Printer = null,
    testContext: ?*TestContext = null,
};

pub const InfoOpts = struct {
    alloc: ?std.mem.Allocator = null,
    // verbose: bool = false,
    writer: ?Printer = null,
};



var GlobalTestContext: ?*TestContext = null;
var TestContexts: ?std.ArrayList(*TestContext) = null;

pub fn pushTestContext(context: *TestContext, opts: struct { alloc: ?std.mem.Allocator=null }) !void {

    var alloc: std.mem.Allocator = undefined;
    if(opts.alloc != null) {
        alloc = opts.alloc.?;
    }
    else {
        alloc = std.heap.page_allocator;
    }

    if(TestContexts == null) {
        TestContexts = std.ArrayList(*TestContext).init(alloc);
    }

    if(GlobalTestContext == null) {
        GlobalTestContext = context;
    }
    else {
        // Push the current Global TestContext onto our stack.
        try TestContexts.?.append(GlobalTestContext.?);
        GlobalTestContext = context;
    }
}

pub fn popTestContext() void {
    if(TestContexts != null and TestContexts.?.items.len > 0) {
       GlobalTestContext = TestContexts.?.pop();
    }
    else {
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

pub fn expectEqualStr(expected: []const u8, actual: []const u8) !void {
    try GlobalTestContext.?.expectEqualStr(expected, actual);
}

pub fn expectEqual(expected: anytype, actual: anytype) !void {
    try GlobalTestContext.?.expectEqual(expected, actual);
}

pub fn expectNotEqualStr(expected: []const u8, actual: []const u8) !void {
    try GlobalTestContext.?.expectNotEqualStr(expected, actual);
}

pub fn expectNotEqual(expected: anytype, actual: anytype) !void {
    try GlobalTestContext.?.expectNotEqual(expected, actual);
}

fn printChars(writer: *Printer, ch: []const u8, num: usize) !void {
    var n = num;
    while (n > 0) {
        try writer.print("{s}", .{ch});
        n -= 1;
    }
}

fn printTestTime(writer: *Printer, timeNs: u64, printColor: bool) !void {
    try writer.print(" (", .{});
    if(printColor) try writer.print(White, .{});

    const timeNsFloat: f64 = @floatFromInt(timeNs);

    // Seconds
    if(timeNs > 1000_000_000) {
        try writer.print("{d: >6.2} secs", .{timeNsFloat / 1000_000_000.0}); 
    }
    // milliseconds
    else if(timeNs > 1000_000) {
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

    if(printColor) try writer.print(Reset, .{});
    try writer.print(")", .{});
}

fn printGroupSeparatorLine(writer: *Printer, maxTestNameLength: usize, printColor: bool) !void {
     // Print top line of group banner, 21 is the num of chars in a verbose test print
    // regardless of name length.
    if(printColor) try writer.print(DarkGreen, .{});

    try writer.print("# ", .{});
    try printChars(writer, "-", maxTestNameLength + 24 - 2);

    if(printColor) try writer.print(Reset, .{});
    // 
}

/// Looks at the slice of tests and returns an owned slice of TestGroups
/// which can be used to list the available filter tags, for example.
pub fn getGroupList(tests: []const TestFuncInfo, opts: InfoOpts) ![]TestGroup
{
    var alloc: std.mem.Allocator = undefined;
    if(opts.alloc != null) {
        alloc = opts.alloc.?;
    }
    else {
        alloc = std.heap.page_allocator;
    }

    var groupSeen = std.StringHashMap(bool).init(alloc);
    defer groupSeen.deinit();

    var groupList = std.ArrayList(TestGroup).init(alloc);
    defer groupList.deinit();

    for(tests) |t| {
        if(!groupSeen.contains(t.group.tag)) {
            try groupList.append(t.group);
            try groupSeen.put(t.group.tag, true);
        }
    }

    return groupList.toOwnedSlice();
}

fn pushGivenContext(givenContext: *TestContext, alloc: std.mem.Allocator, opts: RunTestOpts) !void
{
    givenContext.verbose = opts.verbose;
    givenContext.printStackTraceOnFail = opts.printStackTraceOnFail;
    givenContext.printColor = !opts.printColor;
    try pushTestContext(givenContext, .{ .alloc = alloc });
}

/// Takes a slice of TestFuncInfo and runs them using the given options
/// to handle filtering and how to display the results.
pub fn runTests(tests: []const TestFuncInfo, opts: RunTestOpts) !bool {
    var alloc: std.mem.Allocator = undefined;
    if(opts.alloc != null) {
        alloc = opts.alloc.?;
    }
    else {
        alloc = std.heap.page_allocator;
    }

    // Handle a potential passed in test context to use and 
    // create a global context if one doesn't exist already.
    var createdOwnContext: bool = false;
    if(GlobalTestContext == null) {
        if(opts.testContext != null) {
            try pushGivenContext(opts.testContext.?, alloc, opts);
        }
        else {
            // Create a global context by pushing one, we'll clean this up at
            // the end of runTests.
            const newContext = try alloc.create(TestContext);
            newContext.* = TestContext.init(alloc, .{ 
                .verbose = opts.verbose, 
                .printStackTraceOnFail = opts.printStackTraceOnFail, 
                .printColor = opts.printColor,
            });
            try pushTestContext(newContext, .{ .alloc = alloc });
            createdOwnContext = true;
        }
    }
    else {
        if(opts.testContext != null) {
            try pushGivenContext(opts.testContext.?, alloc, opts);
        }
    }

    var writer: Printer = undefined;
    var usingDefaultWriter: bool = false;
    if(opts.writer != null) {
        writer = opts.writer.?;
    }
    else {
        writer = try Printer.stdout(alloc);
        usingDefaultWriter = true;
    }

    // Filter on the list of tests based on provided tag filters.
    var testsToRun: []const TestFuncInfo = undefined;
    if(opts.allowFilters != null) {
        var filters = std.StringHashMap(bool).init(alloc);
        defer filters.deinit();
        for(opts.allowFilters.?) |filt| {
            try filters.put(filt, true);
        }

        var tempList = std.ArrayList(TestFuncInfo).init(alloc);
        for(tests) |t| {
            var added: bool = false;
            if(filters.contains(t.group.tag)) {
                try tempList.append(t);
                added = true;
            }

            if(!added) {
                if(filters.contains(t.name)) {
                    try tempList.append(t);
                }
            }
        }

        testsToRun = try tempList.toOwnedSlice();
    }
    else {
        testsToRun = tests;
    }

    // Create a map of tags to the list of tests within that group from
    // the potentially filtered set.
    var groupMap = TestFuncMap.init(alloc);
    defer groupMap.deinit();

    for(testsToRun) |t| {
        if(!groupMap.contains(t.group.tag)) {
            const group = TestFuncGroup.init(t.group.name.?, alloc);
            try groupMap.put(t.group.tag, group);

        }

        var group = groupMap.getPtr(t.group.tag).?;
        try group.tests.append(t);
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
    while(true) {
        const groupTag = groupIterator.next();
        if(groupTag == null) break;

        var group = groupMap.get(groupTag.?.*).?;

        // Clean up the group test memory once done iterating
        defer group.deinit();

        // Print out the name of the current group unless it's the default one.
        if(opts.verbose and group.name.len > 0 and !std.mem.eql(u8, groupTag.?.*, "default")) {
            try printGroupSeparatorLine(&writer, verboseLength, opts.printColor);
           
            try writer.print("\n", .{});
            if(opts.printColor) try writer.print(DarkGreen, .{});
            try writer.print("# ", .{});

            if(opts.printColor) try writer.print(Green, .{});
            try writer.print("{s}\n", .{group.name});

            try printGroupSeparatorLine(&writer, verboseLength, opts.printColor);
            try writer.flush();
        }

        // Run each of the tests for the group.
        for(group.tests.items) |f| {
            const testStartTime = try std.time.Instant.now();

            testsRun += 1;

            const testPrintName = if(f.skip) f.name[5..] else f.name;

            GlobalTestContext.?.setCurrentTest(testPrintName);
            if (opts.verbose) {
                if(f.skip) {
                    try writer.print("\nSkipping ", .{});
                    if(opts.printColor) try writer.print(DarkGray, .{});
                    try writer.print("{s}", .{testPrintName});
                    if(opts.printColor) try writer.print(Reset, .{});
                    try writer.print("..",  .{});
                }
                else {
                    try writer.print("\nRunning ", .{});
                    if(opts.printColor) try writer.print(White, .{});
                    try writer.print("{s}", .{testPrintName});
                    if(opts.printColor) try writer.print(Reset, .{});
                    try writer.print("...",  .{});
                }
                const num = @min(verboseLength - testPrintName.len, 128);
                try printChars(&writer, ".", num);
            }

            // If we are skipping this test, print a jump over arrow.
            if(f.skip) {
                if(opts.printColor) try writer.print(Yellow, .{});
                try writer.print("\u{21b7}", .{});
                if(opts.printColor) try writer.print(Reset, .{});
                testsSkipped += 1;
                continue;
            }

            var errorCaught = false;
            f.func() catch {

                // Print an `X` on test failure.
                if(opts.printColor) try writer.print(Red, .{});
                try writer.print("X", .{});
                if(opts.printColor) try writer.print(Reset, .{});
                errorCaught = true;
                testsFailed += 1;
            };

            // If we passed, print a dot in non-verbose mode and a check-mark in verbose.
            if(!errorCaught) {
                testsPassed += 1;

                if(opts.printColor) try writer.print(Green , .{});

                if (opts.verbose) {
                    try writer.print("\u{2713}", .{});
                } else {
                    try writer.print("\u{22c5}", .{});
                }
                
                if(opts.printColor) try writer.print(Reset, .{});
            }

            const testEndTime = try std.time.Instant.now();
            const testAmountNs = testEndTime.since(testStartTime);

            if(opts.verbose) {
                try printTestTime(&writer, testAmountNs, opts.printColor);
            }

            totalTestTimeNs += testAmountNs;
            try writer.flush();
        }

        if(opts.verbose and group.name.len > 0) {
            try writer.print("\n\n", .{});
        }
    }

    for(GlobalTestContext.?.failures.items) |failure| {
        if(opts.printColor) {
            try writer.print("\n" ++ Red ++ "FAIL " ++ Yellow ++ "{s}" ++ Reset, .{failure.testName});
        }
        else {
            try writer.print("\nFAIL {s}", .{failure.testName});
        }
        try writer.print(": {?s}", .{failure.errorMessage});
        if(opts.printStackTraceOnFail) {
            try writer.print("{?s}\n", .{failure.stackTrace});
        }
            }

    if(opts.printColor) {
        try writer.print("\n\n" ++ White ++ "{} " ++ Green ++ "Passed" ++ Reset ++ ", " ++
            White ++ "{} " ++ Red ++ "Failed" ++ Reset ++ ", " ++
            White ++ "{} " ++ Yellow ++ "Skipped" ++ Reset ++ ", " ++
            White ++ "{} " ++ Cyan ++ "Total Tests" ++ Reset, //"({})"\n\n", 
        .{ 
            testsPassed, 
            testsFailed, 
            testsSkipped,
            testsRun 
        });
    }
    else {
        try writer.print("\n\n{} Passed, {} Failed, {} Skipped, {} Total Tests", 
        .{ 
            testsPassed, 
            testsFailed, 
            testsSkipped,
            testsRun 
        });
    }

    try printTestTime(&writer, totalTestTimeNs, opts.printColor);
    try writer.print("\n", .{});
    try writer.flush();

    // Clean up the slice we created if we had filters.
    if(opts.allowFilters != null) {
        alloc.free(testsToRun);
    }

    if(usingDefaultWriter) {
        writer.deinit();
    }

    if(createdOwnContext) {
        const gtcAlloc = GlobalTestContext.?.alloc;
        GlobalTestContext.?.deinit();
        gtcAlloc.destroy(GlobalTestContext.?);
        popTestContext();
    }

    return testsFailed == 0;
}




// Vendored argument parsing lib.
const zargs = @import("lib/zargunaught.zig");
const Option = zargs.Option;

/// A default test runner implementation that parses the command line for options and runs the passed in tests.
/// It allows for verbose/non-verbose output, disabling printing stack traces and providing a list of
/// filter tags to only run some tests.
pub fn testzRunner(testsToRun: []const TestFuncInfo) !void {
    var parser = try zargs.ArgParser.init(
        std.heap.page_allocator, .{ 
            .name = "Unit tests", 
            .description = "Unit tests....", 
            .opts = &[_]Option{
                Option{ .longName = "verbose", .shortName = "v", .description = "Verbose output", .maxNumParams = 0 },
                Option{ .longName = "stack_trace", .shortName = "s", .description = "Print stack traces on errors", .maxNumParams = 0 },
                Option{ .longName = "groups", .shortName = "g", .description = "Lists the groups of tests", .maxNumParams = 0 },
                Option{ .longName = "no-color", .description = "Disables color output", .maxNumParams = 0 },
            } 
        });
    defer parser.deinit();

    var args = parser.parse() catch |err| {
        std.debug.print("Error parsing args: {any}\n", .{err});
        return;
    };
    defer args.deinit();

    // List out the available group tags and names.
    if(args.hasOption("groups")) {
        var printer = try Printer.stdout(std.heap.page_allocator);
        defer printer.deinit();

        const groups = try getGroupList(testsToRun, .{});
        try printer.print("# Test groups:\n", .{});
        for(groups) |g| {
            try printer.print("{s}: {?s}\n", .{g.tag, g.name});
        }
        try printer.flush();

        std.heap.page_allocator.free(groups);
    }
    // Run the tests in this case.
    else {
        const verbose = args.hasOption("verbose");
        const optPrintStackTrace = args.hasOption("stack_trace");
        const optPrintNoColor = args.hasOption("no-color");

        const filters = (if(args.positional.items.len > 0) blk: {
            break :blk args.positional.items;
        } else null);

        // var memBuff = try Printer.memory(std.heap.page_allocator);
        // defer memBuff.deinit();

        _ = try runTests(
            testsToRun,
            .{
                .verbose = verbose,
                .allowFilters = filters,
                .printStackTraceOnFail = optPrintStackTrace,
                .printColor = !optPrintNoColor,
                // .writer = memBuff,
            }
        );
    }
}
