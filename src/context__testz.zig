const std = @import("std");
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
                try self.handleTestError("Expected " ++ White ++ "\"{s}\"" ++ Reset ++ " to be \"{s}\". Differs at index {}, expected=\"{c}\", actual=\"{c}\"" ++ Reset, .{ expected, actual, idx.?, expected[idx.?], actual[idx.?] });
            } else {
                try self.handleTestError("Expected \"{s}\" to be \"{s}\". Differs at index {}, expected=\"{c}\", actual=\"{c}\"", .{ expected, actual, idx.?, expected[idx.?], actual[idx.?] });
            }
            return error.TestExpectedEqual;
        }
    }

    pub fn expectEqual(self: *TestContext, actual: anytype, expected: anytype) !void {
        const T = @TypeOf(actual);
        const ExT = @TypeOf(expected);
        var testFailed = false;
        switch (@typeInfo(T)) {
            .Optional => {
                if (actual) |payload| {
                    switch (@typeInfo(ExT)) {
                        .Optional => {
                            testFailed = (expected == null) or (payload != expected.?);
                        },
                        else => {
                            testFailed = (expected != payload);
                        },
                    }
                } else {
                    switch (@typeInfo(ExT)) {
                        .Optional => {
                            testFailed = (expected != null);
                        },
                        .Null => {},
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
                try self.handleTestError("Expected " ++ White ++ "{any}" ++ Reset ++ " to be {any}" ++ Reset, .{ expected, actual });
            } else {
                try self.handleTestError("Expected {any} to be {any}", .{ expected, actual });
            }
            return error.TestExpectedEqual;
        }
    }

    pub fn expectNotEqualStr(self: *TestContext, actual: []const u8, expected: []const u8) !void {
        if (std.mem.eql(u8, expected, actual) == true) {
            if (self.printColor) {
                try self.handleTestError("Expected " ++ White ++ "\"{s}\"" ++ Reset ++ " to NOT be \"{s}\"" ++ Reset, .{ expected, actual });
            } else {
                try self.handleTestError("Expected \"{s}\" to NOT be \"{s}\"", .{ expected, actual });
            }
            return error.TestExpectedNotEqual;
        }
    }

    pub fn expectNotEqual(self: *TestContext, actual: anytype, expected: anytype) !void {
        if (expected == actual) {
            if (self.printColor) {
                try self.handleTestError("Expected " ++ White ++ "{any}" ++ Reset ++ " to NOT be {any}" ++ Reset, .{ expected, actual });
            } else {
                try self.handleTestError("Expected {any} to NOT be {any}", .{ expected, actual });
            }
            return error.TestExpectedNotEqual;
        }
    }
};

// ----------------------------------------------------------------------------
// Stack tracing helpers
// Code mostly pulled from std.debug directly.
// ----------------------------------------------------------------------------
fn printLinesFromFileAnyOs(out_stream: anytype, line_info: std.debug.LineInfo, context_amount: u64, printColor: bool) !void {
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

        if (amt_read < buf.len) return error.EndOfFile;
    }
}

// A stack trace printing function, using mostly code from std.debug
// Modified to print out more context from the file and add some
// extra highlighting.
fn printStackTrace(failure: *TestFailure, printColor: bool) !void {
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
        defer symbol_info.deinit(debug_info.allocator);

        if (std.mem.eql(u8, symbol_info.symbol_name, "posixCallMainAndExit"))
            break;

        const line_info = symbol_info.line_info;
        if (line_info) |*li| {

            // Skip printing frames within the framework.
            if (std.mem.endsWith(u8, li.file_name, "__testz.zig")) continue;
            if (std.mem.endsWith(u8, li.file_name, "/testz.zig")) continue;
            // Skip over the call to runTests, assuming it's in `main`
            if (std.mem.eql(u8, symbol_info.symbol_name, "main")) continue;

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
