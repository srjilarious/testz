// zig fmt: off
const std = @import("std");
const builtin = @import("builtin");
const native_os = builtin.os.tag;

const DarkGray = "\x1b[90m";
const Red = "\x1b[91m";
const DarkGreen = "\x1b[32m";
const Green = "\x1b[92m";
const Blue = "\x1b[94m";
const Cyan = "\x1b[96m";
const Yellow = "\x1b[93m";
const White = "\x1b[97m";

const Reset = "\x1b[0m";

pub const TestFunc = *const fn () anyerror!void;
pub const TestFuncInfo = struct { 
    func: TestFunc, 
    name: []const u8,
    group: TestGroup,
    skip: bool = false,
};

// Unpacked information from Group, not counting the module.
// This is stored along with each test, since that was much easier
// to get working in comptime than creating a hierarchy of objects.
pub const TestGroup = struct {
    name: ?[]const u8,
    tag: []const u8,
};

// Struct for how a module can be passed in and associated as a group.
pub const Group = struct {
    name: [] const u8,
    // The string for filtering on.
    tag: []const u8, 
    mod: type
};

// A group as used at runtime.
const TestFuncGroup = struct {
    name: []const u8,
    tests: std.ArrayList(TestFuncInfo),

    pub fn init(name: []const u8, alloc: std.mem.Allocator) TestFuncGroup {
        return .{
            .name = name,
            .tests = std.ArrayList(TestFuncInfo).init(alloc)
        };
    }

    pub fn deinit(self: *TestFuncGroup) void {
        self.tests.deinit();
    }
};

const TestFuncMap = std.StringHashMap(TestFuncGroup);

pub const RunTestOpts = struct {
    alloc: ?std.mem.Allocator = null,
    allowFilters: ?[]const []const u8 = null,
    verbose: bool = false,
    printStackTraceOnFail: bool = true,
};

pub fn discoverTestsInModule(comptime groupInfo: TestGroup, comptime mod: type) []const TestFuncInfo {

    comptime var numTests: usize = 0;
    const decls = @typeInfo(mod).Struct.decls;
    inline for (decls) |decl| {
        const fld = @field(mod, decl.name);
        const ti = @typeInfo(@TypeOf(fld));
        if (ti == .Fn) {
            if (std.mem.endsWith(u8, decl.name, "Test")) {
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
            if (std.mem.endsWith(u8, decl.name, "Test")) {
                const skip = std.mem.startsWith(u8, decl.name, "skip_");
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

pub fn discoverTests(comptime mods: anytype) []const TestFuncInfo {
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
            if(@TypeOf(currIndexItem) == Group) {
                
                currGroup = .{
                    .name = @field(currIndexItem, "name"),
                    .tag = @field(currIndexItem, "tag"),
                };
                // Grab the mods field from the Group to extract actual tests from.
                break :blk @field(currIndexItem, "mod");
            }
            else {
                currGroup = .{
                    .name = "Default",
                    .tag = "default",
                };
            
                break :blk @field(mods, fieldName);
            }
        };

        const modTests = discoverTestsInModule(currGroup, currMod);
        for (modTests) |t| {
            tests[totalTests] = t;
            totalTests += 1;
        }
    }

    const final: [totalTests]TestFuncInfo = tests[0..totalTests].*;
    return &final;
}

pub const TestFailure = struct { 
    testName: []const u8,
    lineNo: usize,
    errorMessage: ?[]const u8,
    stackTrace: ?[]const u8,
    alloc: std.mem.Allocator,

    pub fn init(testName: []const u8, alloc: std.mem.Allocator) !TestFailure {
        return .{
            .alloc = alloc,
            .testName = try alloc.dupe(u8, testName),
            .lineNo = 0,
            .errorMessage = null,
            .stackTrace = null,
        };
    }

    pub fn deinit(self: *TestFailure) void {
        self.alloc.free(self.testName);
        self.alloc.free(self.errorMessage);
        self.alloc.free(self.stackTrace);
    }
};

pub const TestContext = struct { 
    failures: std.ArrayList(TestFailure),
    alloc: std.mem.Allocator,
    verbose: bool,
    printStackTraceOnFail: bool,
    currTestName: ?[]const u8,

    fn init(alloc: std.mem.Allocator, verbose: bool, printStackTraceOnFail: bool) TestContext {
        return .{
            .failures = std.ArrayList(TestFailure).init(alloc),
            .alloc = alloc,
            .verbose = verbose,
            .printStackTraceOnFail = printStackTraceOnFail,
            .currTestName = null,
        };
    }

   fn deinit(self: *TestContext) void {
        for(self.failures.items) |f| {
            var fv = f;
            fv.deinit();
        }

        self.alloc.free(self.failures);
    } 

    fn setCurrentTest(self: *TestContext, name: []const u8) void {
        self.currTestName = name;
    }

    fn formatOwnedSliceMessage(alloc: std.mem.Allocator, comptime fmt: []const u8, params: anytype) ![]const u8 {
        var msgBuilder = StringBuilder.init(alloc);
        defer msgBuilder.deinit();
        const writer = msgBuilder.writer();
        try std.fmt.format(writer, fmt, params);
        return msgBuilder.toOwnedSlice();
    }

    fn handleTestError(self: *TestContext, comptime fmt: []const u8, params: anytype) !void {
        var err = try TestFailure.init(self.currTestName.?, self.alloc);
        err.errorMessage = try formatOwnedSliceMessage(self.alloc, fmt, params);
        if(self.printStackTraceOnFail) {
            try printStackTrace(&err);
        }

        try self.failures.append(err);
    }

    fn fail(self: *TestContext) !void {
        try self.handleTestError("Test hit failure point.", .{});
        return error.TestFailed;
    }

    fn failWith(self: *TestContext, err: anytype) !void {
        try self.handleTestError("Test hit failure point: {}", .{err});
        return error.TestFailed;
    }

    fn expectTrue(self: *TestContext, actual: bool) !void {
        if(actual != true) {
            try self.handleTestError("Expected " ++ White ++ "{}" ++ Reset ++ " to be true" ++ Reset, .{actual});
            return error.TestExpectedTrue;
        }
    }

    fn expectFalse(self: *TestContext, actual: bool) !void {
        if(actual == true) {
            try self.handleTestError("Expected " ++ White ++ "{}" ++ Reset ++ " to be false " ++ Reset, .{actual});
            return error.TestExpectedFalse;
        }
    }

    fn expectEqualStr(self: *TestContext, expected: []const u8, actual: []const u8) !void {
        if(std.mem.eql(u8, expected, actual) == false) {
            try self.handleTestError("Expected " ++ White ++ "{s}" ++ Reset ++ " to be {s} " ++ Reset, .{actual, expected});
            return error.TestExpectedEqual;
        }
    }
    
    fn expectEqual(self: *TestContext, expected: anytype, actual: anytype) !void {
        if(expected != actual) {
            try self.handleTestError("Expected " ++ White ++ "{}" ++ Reset ++ " to be {} " ++ Reset, .{actual, expected});
            return error.TestExpectedEqual;
        }
    }
    
    fn expectNotEqualStr(self: *TestContext, expected: []const u8, actual: []const u8) !void {
        if(std.mem.eql(u8, expected, actual) == true) {
            try self.handleTestError("Expected " ++ White ++ "{s}" ++ Reset ++ " to NOT be {s} " ++ Reset, .{actual, expected});
            return error.TestExpectedNotEqual;
        }
    }

    fn expectNotEqual(self: *TestContext, expected: anytype, actual: anytype) !void {
        if(expected == actual) {
           try self.handleTestError("Expected " ++ White ++ "{}" ++ Reset ++ " to NOT be {} " ++ Reset, .{actual, expected});
           return error.TestExpectedNotEqual;
        }
    }
};

var GlobalTestContext: ?TestContext = null;

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

fn printChars(ch: []const u8, num: usize) void {
    var n = num;
    while (n > 0) {
        std.debug.print("{s}", .{ch});
        n -= 1;
    }
}

fn printTestTime(timeNs: u64) void {
    std.debug.print(" (" ++ White, .{});

    const timeNsFloat: f64 = @floatFromInt(timeNs);

    // Seconds
    if(timeNs > 1000_000_000) {
        std.debug.print("{d:.2} secs", .{timeNsFloat / 1000_000_000.0}); 
    }
    // milliseconds
    else if(timeNs > 1000_000) {
        std.debug.print("{d:.2} ms", .{timeNsFloat / 1000_000.0}); 
    }
    // microseconds
    else if (timeNs > 1000) {
        std.debug.print("{d:.2} \u{03bc}s", .{timeNsFloat / 1000.0});
    }
    // nanoseconds.
    else {
        std.debug.print("{} ns", .{timeNs});
    }
    std.debug.print(Reset ++ ")", .{});
}
pub fn runTests(tests: []const TestFuncInfo, opts: RunTestOpts) !bool {
    var alloc: std.mem.Allocator = undefined;
    if(opts.alloc != null) {
        alloc = opts.alloc.?;
    }
    else {
        alloc = std.heap.page_allocator;
    }

    GlobalTestContext = TestContext.init(alloc, opts.verbose, opts.printStackTraceOnFail);

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

    std.debug.print("\n", .{});

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
        
        if(opts.verbose and group.name.len > 0 and !std.mem.eql(u8, groupTag.?.*, "default")) {
            // Print top line of group banner, 12 is the num of chars in a verbose test print
            // regardless of name length.
            std.debug.print(DarkGreen ++ "# ", .{});
            printChars("-", verboseLength + 12 - 2);
            std.debug.print(Reset ++ "\n", .{});

            std.debug.print(DarkGreen ++ "# " ++ Green ++ "{s}\n", .{group.name});

            std.debug.print(DarkGreen ++ "# ", .{});
            printChars("-", verboseLength + 12 - 2);
            std.debug.print(Reset, .{});
        }

        // Run each of the tests for the group.
        for(group.tests.items) |f| {
            const testStartTime = try std.time.Instant.now();

            testsRun += 1;

            const testPrintName = if(f.skip) f.name[5..] else f.name;
            
            GlobalTestContext.?.setCurrentTest(testPrintName);
            if (opts.verbose) {
                if(f.skip) {
                    std.debug.print("\nSkipping " ++ DarkGray ++ "{s}" ++ Reset ++ "..", 
                        .{testPrintName});
                }
                else {
                    std.debug.print("\nRunning " ++ White ++ "{s}" ++ Reset ++ "...", 
                        .{testPrintName});
                }
                const num = @min(verboseLength - testPrintName.len, 128);
                printChars(".", num);
            }

            if(f.skip) {
                std.debug.print(Yellow ++ "\u{21b7}" ++ Reset, .{});
                testsSkipped += 1;
                continue;
            }

            var errorCaught = false;
            f.func() catch {
                std.debug.print(Red ++ "X" ++ Reset, .{});
                errorCaught = true;
                testsFailed += 1;
            };

            if(!errorCaught) {
                testsPassed += 1;

                if (opts.verbose) {
                    std.debug.print(Green ++ "\u{2713}" ++ Reset, .{});
                } else {
                    std.debug.print(Green ++ "\u{22c5}" ++ Reset, .{});
                }
            }

            const testEndTime = try std.time.Instant.now();
            const testAmountNs = testEndTime.since(testStartTime);

            if(opts.verbose) {
                printTestTime(testAmountNs);
            }

            totalTestTimeNs += testAmountNs;
        }

        if(opts.verbose and group.name.len > 0) {
            std.debug.print("\n\n", .{});
        }
    }

    for(GlobalTestContext.?.failures.items) |failure| {
        std.debug.print("\n" ++ Red ++ "FAIL " ++ Yellow ++ "{s}" ++ Reset, .{failure.testName});
        // if(opts.verbose) {
            std.debug.print(": {?s}", .{failure.errorMessage});
            if(opts.printStackTraceOnFail) {
                std.debug.print("{?s}\n", .{failure.stackTrace});
            }
        // }
        // else {
            // if(opts.printStackTraceOnFail) {
            //     // Try to roughly align the lines to the end of the bottom status report.
            //     printChars(" ", @max(30, verboseLength) - failure.testName.len);
            //     std.debug.print("   line {}", .{failure.lineNo});
            // }
        // }
    }

    std.debug.print("\n\n" ++ White ++ "{} " ++ Green ++ "Passed" ++ Reset ++ ", " ++
        White ++ "{} " ++ Red ++ "Failed" ++ Reset ++ ", " ++
        White ++ "{} " ++ Yellow ++ "Skipped" ++ Reset ++ ", " ++
        White ++ "{} " ++ Cyan ++ "Total Tests" ++ Reset, //"({})"\n\n", 
    .{ 
        testsPassed, 
        testsFailed, 
        testsSkipped,
        testsRun 
    });

    printTestTime(totalTestTimeNs);
    // Clean up the slice we created if we had filters.
    if(opts.allowFilters != null) {
        alloc.free(testsToRun);
    }

    // Fix me.
    // GlobalTestContext.?.deinit();
    return testsFailed == 0;
}

const StringBuilder = std.ArrayList(u8);

// ----------------------------------------------------------------------------
// Stack tracing helpers
// Code mostly pulled from std.debug directly.
// ----------------------------------------------------------------------------
fn printLinesFromFileAnyOs(out_stream: anytype, line_info: std.debug.LineInfo, context_amount: u64) !void {
    // Need this to always block even in async I/O mode, because this could potentially
    // be called from e.g. the event loop code crashing.
    var f = try std.fs.cwd().openFile(line_info.file_name, .{});
    defer f.close();
    // TODO fstat and make sure that the file has the correct size

    const min_line: u64 = line_info.line -| context_amount;
    const max_line: u64 = line_info.line +| context_amount;

    var buf: [std.mem.page_size]u8 = undefined;
    var line: usize = 1;
    var column: usize = 1;
    while (true) {
        const amt_read = try f.read(buf[0..]);
        const slice = buf[0..amt_read];

        for (slice) |byte| {
            if (line >= min_line and line <= max_line) {
                //if (line == line_info.line) {
                switch (byte) {
                    '\t' => try out_stream.writeByte(' '),
                    else => try out_stream.writeByte(byte),
                }
                if (byte == '\n' and line == max_line) {
                    return;
                }
            }
            if (byte == '\n') {
                line += 1;
                if (line >= min_line and line <= max_line) {
                    try std.fmt.format(out_stream, White ++ "{d: >5}", .{line});
                    if (line == line_info.line) {
                        _ = try out_stream.write(" --> " ++ Reset);
                    } else {
                        _ = try out_stream.write("     " ++ Reset);
                    }
                }
                column = 1;
            } else {
                column += 1;
            }
        }

        if (line > max_line) return;

        if (amt_read < buf.len) return error.EndOfFile;
    }
}

// A stack trace printing function, using mostly code from std.debug
// Modified to print out more context from the file and add some 
// extra highlighting.
fn printStackTrace(failure: *TestFailure) !void {
    const stderr = std.io.getStdErr().writer();
    if (builtin.strip_debug_info) {
        stderr.print("Unable to dump stack trace: debug info stripped\n", .{}) catch return;
        return;
    }
    const debug_info = std.debug.getSelfDebugInfo() catch |err| {
        stderr.print("Unable to dump stack trace: Unable to open debug info: {s}\n", .{@errorName(err)}) catch return;
        return;
    };

    const tty_config = std.io.tty.detectConfig(std.io.getStdErr());
    _ = tty_config;
    var context: std.debug.ThreadContext = undefined;
    const has_context = std.debug.getContext(&context);
    if (native_os == .windows) {
        @panic("Windows not supported yet.");
        //return writeStackTraceWindows(out_stream, debug_info, tty_config, &context, start_addr);
    }

    var it = (if (has_context) blk: {
        break :blk std.debug.StackIterator.initWithContext(null, debug_info, &context) catch null;
    } else null) orelse std.debug.StackIterator.init(null, null);
    defer it.deinit();

    var trace = StringBuilder.init(failure.alloc);
    // Preallocate some space for the stack trace.
    try trace.ensureTotalCapacity(2048);
    const out_stream = trace.writer();
    defer trace.deinit();
    var first = true;
    while (it.next()) |return_address| {
        const module = debug_info.getModuleForAddress(return_address) catch |err| switch (err) {
            error.MissingDebugInfo, error.InvalidDebugInfo => return, //printUnknownSource(debug_info, out_stream, address, tty_config),
            else => return err,
        };

        const symbol_info = module.getSymbolAtAddress(debug_info.allocator, return_address) catch |err| switch (err) {
            error.MissingDebugInfo, error.InvalidDebugInfo => return, // printUnknownSource(debug_info, out_stream, address, tty_config),
            else => return err,
        };
        defer symbol_info.deinit(debug_info.allocator);

        if (std.mem.eql(u8, symbol_info.symbol_name, "posixCallMainAndExit"))
            break;

        const line_info = symbol_info.line_info;
        if (line_info) |*li| {
            
            // Skip printing frames within the framework.
            if(std.mem.endsWith(u8, li.file_name, "testz.zig")) continue;
            // Skip over the call to runTests, assuming it's in `main`
            if(std.mem.eql(u8, symbol_info.symbol_name, "main")) continue;

            // std.debug.print("*** Symbol: {s}, {s}\n", .{symbol_info.symbol_name, symbol_info.compile_unit_name});
            try std.fmt.format(out_stream, "\n{s}:" ++ White ++ "{d}" ++ Reset ++ ":{d}:\n", .{ li.file_name, li.line, li.column });

            if(first) {
                failure.lineNo = li.line;
                first = false;
            }
        } else {
            _ = try out_stream.write("???:?:?\n");
        }

        // try stderr.print(" 0x{x} in {s} ({s})\n\n", .{ return_address, symbol_info.symbol_name, symbol_info.compile_unit_name });

        if (line_info) |li| {
            try printLinesFromFileAnyOs(out_stream, li, 3);
        }
    }

    failure.stackTrace = try trace.toOwnedSlice();

    // std.debug.writeCurrentStackTrace(stderr, debug_info, std.io.tty.detectConfig(std.io.getStdErr()), null) catch |err| {
    //     stderr.print("Unable to dump stack trace: {s}\n", .{@errorName(err)}) catch return;
    //     return;
    // };
}


// Vendored argument parsing lib.
const zargs = @import("lib/zargunaught.zig");
const Option = zargs.Option;

// Parses the command line for options and runs the passed in tests.
pub fn testzRunner(testsToRun: []const TestFuncInfo) !void {
    var parser = try zargs.ArgParser.init(
        std.heap.page_allocator, .{ 
            .name = "Unit tests", 
            .description = "Unit tests....", 
            .opts = &[_]Option{
                Option{ .longName = "verbose", .shortName = "v", .description = "Verbose output", .maxNumParams = 0 },
                Option{ .longName = "stack_trace", .shortName = "s", .description = "Print stack traces on errors", .maxNumParams = 0 },
            } 
        });
    defer parser.deinit();

    var args = parser.parse() catch |err| {
        std.debug.print("Error parsing args: {any}\n", .{err});
        return;
    };
    defer args.deinit();

    const verbose = args.hasOption("verbose");
    const optPrintStackTrace = args.hasOption("stack_trace");

    const filters = (if(args.positional.items.len > 0) blk: {
        break :blk args.positional.items;
    } else null);

    _ = try runTests(
        testsToRun,
        .{
            .verbose = verbose,
            .allowFilters = filters,
            .printStackTraceOnFail = optPrintStackTrace
        }
    );
}
