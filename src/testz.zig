// zig fmt: off
const std = @import("std");
const builtin = @import("builtin");
const native_os = builtin.os.tag;

const DarkGray = "\x1b[90m";
const Red = "\x1b[91m";
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
    skip: bool
};

pub fn discoverTestsInModule(comptime mod: type) []TestFuncInfo {

    // @compileLog(@typeInfo(andTests).Struct.decls);
    var numTests: usize = 0;
    for (std.meta.declarations(mod)) |decl| {
        const fld = @field(mod, decl.name);
        const ti = @typeInfo(@TypeOf(fld));
        if (ti == .Fn) {
            if (std.mem.endsWith(u8, decl.name, "Test")) {
                numTests += 1;
                // @compileLog("Found TEST: ", numTests);
            }
        }
    }

    comptime var tests: [numTests]TestFuncInfo = undefined;
    var idx: usize = 0;
    for (std.meta.declarations(mod)) |decl| {
        const fld = @field(mod, decl.name);
        const ti = @typeInfo(@TypeOf(fld));
        if (ti == .Fn) {
            if (std.mem.endsWith(u8, decl.name, "Test")) {
                const skip = std.mem.startsWith(u8, decl.name, "skip_");
                // @compileLog("Adding TEST: " ++ decl.name);
                tests[idx] = .{ 
                    .func = fld, 
                    .name = decl.name,
                    .skip = skip,
                };
                idx += 1;
            }
        }
    }

    return &tests;
    // @compileLog(tests);
}

pub fn discoverTests(comptime mods: anytype) []TestFuncInfo {
    const ModsType = @TypeOf(mods);
    const modsTypeInfo = @typeInfo(ModsType);
    if (modsTypeInfo != .Struct) {
        @compileError("expected tuple or struct argument of modules, found " ++ @typeName(ModsType));
    }

    const fieldsInfo = modsTypeInfo.Struct.fields;
    const MaxTests = 10000;
    comptime var tests: [MaxTests]TestFuncInfo = undefined;
    comptime var totalTests: usize = 0;
    var fieldIdx = 0;
    inline for (fieldsInfo) |_| {
        const fieldName = std.fmt.comptimePrint("{}", .{fieldIdx});
        fieldIdx += 1;
        const currMod = @field(mods, fieldName);
        const modTests = discoverTestsInModule(currMod);
        for (modTests) |t| {
            tests[totalTests] = t;
            totalTests += 1;
        }
    }

    return tests[0..totalTests];
}

pub const TestFailure = struct { 
    //testName: [256]u8, 
    lineNo: usize, 
    errorMessage: []u8,
    // stackTrace: []u8
};

pub const TestContext = struct { 
    failures: std.ArrayList(TestFailure),
    alloc: std.mem.Allocator,
    verbose: bool,
    currTestName: ?[]const u8,

    fn init(alloc: std.mem.Allocator, verbose: bool) TestContext {
        return .{
            .failures = std.ArrayList(TestFailure).init(alloc),
            .alloc = alloc,
            .verbose = verbose,
            .currTestName = null,
        };
    }

    fn deinit(self: *TestContext) void {
        for(self.failures) |fail| {
            self.alloc.free(fail.errorMessage);
        }
        self.alloc.free(self.failures);
    }

    fn setCurrentTest(self: *TestContext, name: []const u8) void {
        self.currTestName = name;
    }

    fn expectTrue(self: *TestContext, actual: anytype) !void {
        if(actual != true) {
            // Print the test failed.
            std.debug.print(Red ++ "X" ++ Reset ++ "\n\n", .{});

            if(self.verbose) {
                // If verbose, we don't need to print the test name in the fail message
                // since it will already show up in the list of tests running.
                std.debug.print(Red ++ "FAIL" ++ Reset ++ ": ", .{});
            }
            else {
                std.debug.print(Red ++ "FAIL " ++ Yellow ++ "{?s}" ++ Reset ++ ": ", .{self.currTestName});
            }

            std.debug.print("Expected " ++ White ++ "{}" ++ Reset ++ " to be true " ++ Reset ++ "\n", 
                .{actual});

            printStackTrace() catch {
                // std.debug.print("Unable to print stack trace: {}", .{err});
            };

            std.debug.print("\n", .{});
            return error.TestExpectedTrue;
        }
    }

    fn expectEqual(self: *TestContext, expected: anytype, actual: anytype) !void {
        if(expected != actual) {
            // Print the test failed.
            std.debug.print(Red ++ "X" ++ Reset ++ "\n\n", .{});

            if(self.verbose) {
                // If verbose, we don't need to print the test name in the fail message
                // since it will already show up in the list of tests running.
                std.debug.print(Red ++ "FAIL" ++ Reset ++ ": ", .{});
            }
            else {
                std.debug.print(Red ++ "FAIL " ++ Yellow ++ "{?s}" ++ Reset ++ ": ", .{self.currTestName});
            }

            std.debug.print("Expected " ++ White ++ "{}" ++ Reset ++ " == " ++ White ++ "{}" ++ Reset ++ "\n", 
                .{expected, actual});

            printStackTrace() catch {
                // std.debug.print("Unable to print stack trace: {}", .{err});
            };

            std.debug.print("\n", .{});
            return error.TestExpectedEqual;
        }
    }
};

var GlobalTestContext: ?TestContext = null;//TestContext.init();

pub fn expectTrue(actual: anytype) !void {
    try GlobalTestContext.?.expectTrue(actual);
}

pub fn expectEqual(expected: anytype, actual: anytype) !void {
    try GlobalTestContext.?.expectEqual(expected, actual);
}

pub fn runTests(tests: []const TestFuncInfo, verbose: bool) bool {
    GlobalTestContext = TestContext.init(std.heap.page_allocator, verbose);

    if (verbose) {
        std.debug.print("\nRunning {} tests:\n", .{tests.len});
    } 
    else {
        std.debug.print("\n", .{});
    }

    var testsRun: u32 = 0;
    var testsPassed: u32 = 0;
    var testsFailed: u32 = 0;
    var testsSkipped: u32 = 0;

    // Find the longest length name in the tests for formatting.
    var verboseLength: usize = 0;
    if (verbose) {
        for (tests) |f| {
            if (f.name.len > verboseLength) {
                verboseLength = f.name.len;
            }
        }
    }

    // Run each of the tests.
    for (tests) |f| {
        testsRun += 1;

        const testPrintName = if(f.skip) f.name[5..] else f.name;

        GlobalTestContext.?.setCurrentTest(testPrintName);
        if (verbose) {
            std.debug.print("\nRunning " ++ "{s}{s}" ++ Reset ++ "...", .{
                if(f.skip) DarkGray else White,
                testPrintName});
            var num = @min(verboseLength - testPrintName.len, 128);
            while (num > 0) {
                std.debug.print(".", .{});
                num -= 1;
            }
        }

        if(f.skip) {
            std.debug.print(Yellow ++ "\u{21b7}" ++ Reset, .{});
            testsSkipped += 1;
            continue;
        }

        const res = f.func();
        if (res != error.TestExpectedEqual) {
            testsPassed += 1;

            if (verbose) {
                std.debug.print(Green ++ "\u{2713}" ++ Reset, .{});
            } else {
                std.debug.print(Green ++ "." ++ Reset, .{});
            }
        } else {
            testsFailed += 1;
            // std.debug.print(Red ++ "X" ++ Reset, .{});
        }
    }

    //std.debug.print(Green ++ "\nDone!\n\n" ++ Reset, .{});
    std.debug.print("\n\n" ++ White ++ "{} " ++ Green ++ "Passed" ++ Reset ++ ", " ++
        White ++ "{} " ++ Red ++ "Failed" ++ Reset ++ ", " ++
        White ++ "{} " ++ Yellow ++ "Skipped" ++ Reset ++ ", " ++
        White ++ "{} " ++ Cyan ++ "Total Tests" ++ Reset ++ "\n\n", 
    .{ 
        testsPassed, 
        testsFailed, 
        testsSkipped,
        testsRun 
    });


    // Testing
    // for(GlobalTestContext.?.failures.items) |fail| {
    //     std.debug.print("{s}\n", .{fail.errorMessage});
    // }
    return testsFailed == 0;
}


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
fn printStackTrace() !void {
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

            try stderr.print("\n{s}:" ++ White ++ "{d}" ++ Reset ++ ":{d}:\n", .{ li.file_name, li.line, li.column });
        } else {
            try stderr.writeAll("???:?:?\n");
        }

        // try stderr.print(" 0x{x} in {s} ({s})\n\n", .{ return_address, symbol_info.symbol_name, symbol_info.compile_unit_name });

        if (line_info) |li| {
            try printLinesFromFileAnyOs(stderr, li, 3);
        }
    }

    // std.debug.writeCurrentStackTrace(stderr, debug_info, std.io.tty.detectConfig(std.io.getStdErr()), null) catch |err| {
    //     stderr.print("Unable to dump stack trace: {s}\n", .{@errorName(err)}) catch return;
    //     return;
    // };
}

