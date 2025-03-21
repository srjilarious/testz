const std = @import("std");
const io = std.io;

const builtin = @import("builtin");
const native_os = builtin.os.tag;

const core = @import("./core.zig");
const TestFailure = core.TestFailure;
const StringBuilder = core.StringBuilder;

// TEMP: Gonig to refactor into styles with no-tty option.
const DarkGray = "\x1b[90m";
const Red = "\x1b[91m";
const DarkGreen = "\x1b[32m";
const Green = "\x1b[92m";
const Blue = "\x1b[94m";
const Cyan = "\x1b[96m";
const Yellow = "\x1b[93m";
const White = "\x1b[97m";

const Reset = "\x1b[0m";
pub const TestContext = struct {
    failures: std.ArrayList(TestFailure),
    alloc: std.mem.Allocator,
    verbose: bool,
    printStackTraceOnFail: bool,
    printColor: bool,
    currTestName: ?[]const u8,

    pub fn init(alloc: std.mem.Allocator, opts: struct { verbose: bool = false, printStackTraceOnFail: bool = true, printColor: bool = true }) TestContext {
        return .{
            .failures = std.ArrayList(TestFailure).init(alloc),
            .alloc = alloc,
            .verbose = opts.verbose,
            .printStackTraceOnFail = opts.printStackTraceOnFail,
            .printColor = opts.printColor,
            .currTestName = null,
        };
    }

    pub fn deinit(self: *TestContext) void {
        for (self.failures.items) |f| {
            var fv = f;
            fv.deinit();
        }

        self.failures.deinit();
    }

    pub fn setCurrentTest(self: *TestContext, name: []const u8) void {
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
        if (self.printStackTraceOnFail) {
            try printStackTrace(&err, self.printColor);
        }

        try self.failures.append(err);
    }

    pub fn fail(self: *TestContext) !void {
        try self.handleTestError("Test hit failure point.", .{});
        return error.TestFailed;
    }

    pub fn failWith(self: *TestContext, err: anytype) !void {
        if (self.printColor) {
            try self.handleTestError("Test hit failure point: " ++ White ++ "{any}" ++ Reset, .{err});
        } else {
            try self.handleTestError("Test hit failure point: {any}", .{err});
        }

        return error.TestFailed;
    }

    pub fn expectTrue(self: *TestContext, actual: bool) !void {
        if (actual != true) {
            if (self.printColor) {
                try self.handleTestError("Expected " ++ White ++ "{}" ++ Reset ++ " to be true" ++ Reset, .{actual});
            } else {
                try self.handleTestError("Expected {} to be true", .{actual});
            }
            return error.TestExpectedTrue;
        }
    }

    pub fn expectFalse(self: *TestContext, actual: bool) !void {
        if (actual == true) {
            if (self.printColor) {
                try self.handleTestError("Expected " ++ White ++ "{}" ++ Reset ++ " to be false" ++ Reset, .{actual});
            } else {
                try self.handleTestError("Expected {} to be false", .{actual});
            }
            return error.TestExpectedFalse;
        }
    }

    pub fn expectEqualStr(self: *TestContext, actual: []const u8, expected: []const u8) !void {
        const idx = std.mem.indexOfDiff(u8, expected, actual);
        if (idx != null) {
            if (self.printColor) {
                if (actual.len == expected.len) {
                    try self.handleTestError("Expected " ++ White ++ "\"{s}\"" ++ Reset ++ ", but got \"{s}\". Differs at index {}, expected=\"{c}\", actual=\"{c}\"" ++ Reset, .{ expected, actual, idx.?, expected[idx.?], actual[idx.?] });
                } else {
                    try self.handleTestError("Expected " ++ White ++ "\"{s}\"" ++ Reset ++ ", but got \"{s}\". Lengths differ {} versus {}" ++ Reset, .{ expected, actual, expected.len, actual.len });
                }
            } else {
                if (actual.len == expected.len) {
                    try self.handleTestError("Expected \"{s}\", but got \"{s}\". Differs at index {}, expected=\"{c}\", actual=\"{c}\"", .{ expected, actual, idx.?, expected[idx.?], actual[idx.?] });
                } else {
                    try self.handleTestError("Expected \"{s}\", but got \"{s}\". Lengths differ {} versus {}", .{ expected, actual, expected.len, actual.len });
                }
            }
            return error.TestExpectedEqual;
        }
    }

    // pub fn expectEqualArr(self: *TestContext, T: anytype, actual: []const T, expected: []const T) !void {
    //     const idx = std.mem.indexOfDiff(u8, expected, actual);
    //     if (idx != null) {
    //         if (self.printColor) {
    //             try self.handleTestError("Expected " ++ White ++ "\"{s}\"" ++ Reset ++ " to be \"{s}\". Differs at index {}, expected=\"{c}\", actual=\"{c}\"" ++ Reset, .{ expected, actual, idx.?, expected[idx.?], actual[idx.?] });
    //         } else {
    //             try self.handleTestError("Expected \"{s}\" to be \"{s}\". Differs at index {}, expected=\"{c}\", actual=\"{c}\"", .{ expected, actual, idx.?, expected[idx.?], actual[idx.?] });
    //         }
    //         return error.TestExpectedEqual;
    //     }
    // }

    pub fn expectEqual(self: *TestContext, actual: anytype, expected: anytype) !void {
        const T = @TypeOf(actual);
        const ExT = @TypeOf(expected);
        var testFailed = false;
        switch (@typeInfo(T)) {
            .optional => {
                if (actual) |payload| {
                    switch (@typeInfo(ExT)) {
                        .optional => {
                            testFailed = (expected == null) or (payload != expected.?);
                        },
                        .null => {
                            testFailed = true;
                        },
                        else => {
                            testFailed = (expected != payload);
                        },
                    }
                } else {
                    switch (@typeInfo(ExT)) {
                        .optional => {
                            testFailed = (expected != null);
                        },
                        .null => {},
                        else => {
                            testFailed = true;
                        },
                    }
                }
            },
            else => {
                testFailed = (expected != actual);
            },
        }

        if (testFailed) {
            if (self.printColor) {
                try self.handleTestError("Expected " ++ White ++ "{any}" ++ Reset ++ ", but got {any}" ++ Reset, .{ expected, actual });
            } else {
                try self.handleTestError("Expected {any}, but got {any}", .{ expected, actual });
            }
            return error.TestExpectedEqual;
        }
    }

    pub fn expectNotEqualStr(self: *TestContext, actual: []const u8, expected: []const u8) !void {
        if (std.mem.eql(u8, expected, actual) == true) {
            if (self.printColor) {
                try self.handleTestError("Did NOT expect " ++ White ++ "\"{s}\"" ++ Reset ++ " to be \"{s}\"" ++ Reset, .{ expected, actual });
            } else {
                try self.handleTestError("Did NOT expect \"{s}\" to be \"{s}\"", .{ expected, actual });
            }
            return error.TestExpectedNotEqual;
        }
    }

    pub fn expectNotEqual(self: *TestContext, actual: anytype, expected: anytype) !void {
        const T = @TypeOf(actual);
        const ExT = @TypeOf(expected);
        var testPassed = true;
        switch (@typeInfo(T)) {
            .optional => {
                if (actual) |payload| {
                    switch (@typeInfo(ExT)) {
                        .optional => {
                            testPassed = (expected == null) or (payload != expected.?);
                        },
                        .null => {
                            testPassed = true;
                        },
                        else => {
                            testPassed = (expected != payload);
                        },
                    }
                } else {
                    switch (@typeInfo(ExT)) {
                        .optional => {
                            testPassed = (expected != null);
                        },
                        .null => {},
                        else => {
                            testPassed = true;
                        },
                    }
                }
            },
            else => {
                testPassed = (expected != actual);
            },
        }

        if (!testPassed) {
            if (self.printColor) {
                try self.handleTestError("Did NOT expect " ++ White ++ "{any}" ++ Reset ++ " to be {any}" ++ Reset, .{ expected, actual });
            } else {
                try self.handleTestError("Did NOT expect {any} to be {any}", .{ expected, actual });
            }
            return error.TestExpectedNotEqual;
        }
    }

    pub fn expectError(self: *TestContext, actual: anytype, expected: anyerror) !void {
        const T = @TypeOf(actual);
        switch (@typeInfo(T)) {
            .error_union => {
                if (actual) |a| {
                    if (self.printColor) {
                        try self.handleTestError("Expected error " ++ White ++ "\"{!}\"" ++ Reset ++ ", but got \"{any}\"" ++ Reset, .{ expected, a });
                    } else {
                        try self.handleTestError("Expected error \"{!}\", but got \"{any}\"", .{ expected, a });
                    }

                    return error.TestExpectedError;
                } else |e| {
                    if (e != expected) {
                        if (self.printColor) {
                            try self.handleTestError("Expected " ++ White ++ "\"{!}\"" ++ Reset ++ ", but got \"{!}\"" ++ Reset, .{ actual, e });
                        } else {
                            try self.handleTestError("Expected \"{!}\", but got \"{!}\"", .{ actual, e });
                        }

                        return error.TestExpectedError;
                    }
                }
            },
            else => {
                @compileError("Expected an error or error union type in expectError!");
            },
        }
    }
};

// ----------------------------------------------------------------------------
// Stack tracing helpers
// Code mostly pulled from std.debug directly.
// ----------------------------------------------------------------------------
fn printLinesFromFileAnyOs(out_stream: anytype, line_info: std.debug.SourceLocation, context_amount: u64, printColor: bool) !void {
    // Need this to always block even in async I/O mode, because this could potentially
    // be called from e.g. the event loop code crashing.
    var f = try std.fs.cwd().openFile(line_info.file_name, .{});
    defer f.close();
    // TODO fstat and make sure that the file has the correct size

    const min_line: u64 = line_info.line -| context_amount;
    const max_line: u64 = line_info.line +| context_amount;

    var buf: [2048]u8 = undefined;
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
                    if (printColor) {
                        try std.fmt.format(out_stream, White ++ "{d: >5}", .{line});
                    } else {
                        try std.fmt.format(out_stream, "{d: >5}", .{line});
                    }
                    if (line == line_info.line) {
                        _ = try out_stream.write(" --> ");
                    } else {
                        _ = try out_stream.write("     ");
                    }

                    if (printColor) {
                        _ = try out_stream.write(Reset);
                    }
                }
                column = 1;
            } else {
                column += 1;
            }
        }

        if (line > max_line) return;

        if (amt_read < buf.len) return; // error.EndOfFile;
    }
}

// A stack trace printing function, using mostly code from std.debug
// Modified to print out more context from the file and add some
// extra highlighting.
fn printStackTrace(failure: *TestFailure, printColor: bool) !void {
    // nosuspend {
    if (comptime builtin.target.cpu.arch.isWasm()) {
        if (native_os == .wasi) {
            const stderr = io.getStdErr().writer();
            stderr.print("Unable to dump stack trace: not implemented for Wasm\n", .{}) catch return;
        }
        return;
    }
    const stderr = io.getStdErr().writer();

    //     var trace = StringBuilder.init(failure.alloc);
    //     try trace.ensureTotalCapacity(2048);
    //     const out_stream = trace.writer();
    //     defer trace.deinit();

    if (builtin.strip_debug_info) {
        stderr.print("Unable to dump stack trace: debug info stripped\n", .{}) catch return;
        return;
    }
    const debug_info = std.debug.getSelfDebugInfo() catch |err| {
        stderr.print("Unable to dump stack trace: Unable to open debug info: {s}\n", .{@errorName(err)}) catch return;
        return;
    };

    if (native_os == .windows) {
        var context: std.debug.ThreadContext = undefined;
        const tty_config = io.tty.detectConfig(std.io.getStdErr());
        std.debug.assert(std.debug.getContext(&context));
        return std.debug.writeStackTraceWindows(stderr, debug_info, tty_config, &context, null);
    }

    var context: std.debug.ThreadContext = undefined;
    const has_context = std.debug.getContext(&context);

    var it = (if (has_context) blk: {
        break :blk std.debug.StackIterator.initWithContext(null, debug_info, &context) catch null;
    } else null) orelse std.debug.StackIterator.init(null, null);
    defer it.deinit();

    //     while (it.next()) |return_address| {
    //         printLastUnwindError(&it, debug_info, out_stream, tty_config);

    //         // On arm64 macOS, the address of the last frame is 0x0 rather than 0x1 as on x86_64 macOS,
    //         // therefore, we do a check for `return_address == 0` before subtracting 1 from it to avoid
    //         // an overflow. We do not need to signal `StackIterator` as it will correctly detect this
    //         // condition on the subsequent iteration and return `null` thus terminating the loop.
    //         // same behaviour for x86-windows-msvc
    //         const address = return_address -| 1;
    //         try printSourceAtAddress(debug_info, out_stream, address, tty_config);
    //     } else printLastUnwindError(&it, debug_info, out_stream, tty_config);

    //     // std.debug.writeCurrentStackTrace(out_stream, debug_info, tty_config, null) catch |err| {
    //     //     stderr.print("Unable to dump stack trace: {s}\n", .{@errorName(err)}) catch return;
    //     //     return;
    //     // };

    //     failure.stackTrace = try trace.toOwnedSlice();
    // }

    var trace = StringBuilder.init(failure.alloc);
    // Preallocate some space for the stack trace.
    try trace.ensureTotalCapacity(2048);
    const out_stream = trace.writer();
    defer trace.deinit();
    var first = true;
    while (it.next()) |return_address| {
        const module = debug_info.getModuleForAddress(return_address) catch {
            break;
            // switch (err) {
            //     error.MissingDebugInfo, error.InvalidDebugInfo => return err, //printUnknownSource(debug_info, out_stream, address, tty_config),
            //     else => return err,
            // }
        };

        const symbol_info = module.getSymbolAtAddress(debug_info.allocator, return_address) catch {
            break;
            // switch (err) {
            //     error.MissingDebugInfo, error.InvalidDebugInfo => , // printUnknownSource(debug_info, out_stream, address, tty_config),
            //     else => return err,
            // }
        };
        defer if (symbol_info.source_location) |sl| debug_info.allocator.free(sl.file_name);

        if (std.mem.eql(u8, symbol_info.name, "posixCallMainAndExit"))
            break;

        const line_info = symbol_info.source_location;
        if (line_info) |*li| {

            // Skip printing frames within the framework.
            if (std.mem.endsWith(u8, li.file_name, "__testz.zig")) continue;
            if (std.mem.endsWith(u8, li.file_name, "/testz.zig")) continue;
            // Skip over the call to runTests, assuming it's in `main`
            if (std.mem.eql(u8, symbol_info.name, "main")) continue;

            // std.debug.print("*** Symbol: {s}, {s}\n", .{symbol_info.symbol_name, symbol_info.compile_unit_name});
            if (printColor) {
                std.fmt.format(out_stream, "\n{s}:" ++ White ++ "{d}" ++ Reset ++ ":{d}:\n", .{ li.file_name, li.line, li.column }) catch break;
            } else {
                std.fmt.format(out_stream, "\n{s}:{d}:{d}:\n", .{ li.file_name, li.line, li.column }) catch break;
            }

            if (first) {
                failure.lineNo = li.line;
                first = false;
            }
        } else {
            _ = out_stream.write("???:?:?\n") catch break;
        }

        // try stderr.print(" 0x{x} in {s} ({s})\n\n", .{ return_address, symbol_info.symbol_name, symbol_info.compile_unit_name });

        if (line_info) |li| {
            printLinesFromFileAnyOs(out_stream, li, 3, printColor) catch {};
        }
    }

    if (first) {
        std.fmt.format(out_stream, "No printable stack frames.", .{}) catch {};
    }

    failure.stackTrace = try trace.toOwnedSlice();

    // std.debug.writeCurrentStackTrace(stderr, debug_info, std.io.tty.detectConfig(std.io.getStdErr()), null) catch |err| {
    //     stderr.print("Unable to dump stack trace: {s}\n", .{@errorName(err)}) catch return;
    //     return;
    // };
}
