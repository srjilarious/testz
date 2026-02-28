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
            .failures = .{},
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

        self.failures.deinit(self.alloc);
    }

    pub fn setCurrentTest(self: *TestContext, name: []const u8) void {
        self.currTestName = name;
    }

    fn formatOwnedSliceMessage(alloc: std.mem.Allocator, comptime fmt: []const u8, params: anytype) ![]const u8 {
        var msgBuilder: StringBuilder = .{};
        defer msgBuilder.deinit(alloc);
        try msgBuilder.writer(alloc).print(fmt, params);
        return msgBuilder.toOwnedSlice(alloc);
    }

    fn handleTestError(self: *TestContext, comptime fmt: []const u8, params: anytype) !void {
        var err = try TestFailure.init(self.currTestName.?, self.alloc);
        err.errorMessage = try formatOwnedSliceMessage(self.alloc, fmt, params);
        if (self.printStackTraceOnFail) {
            try printStackTrace(&err, self.printColor);
        }

        try self.failures.append(self.alloc, err);
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
                        try self.handleTestError("Expected error " ++ White ++ "\"{any}\"" ++ Reset ++ ", but got \"{any}\"" ++ Reset, .{ expected, a });
                    } else {
                        try self.handleTestError("Expected error \"{any}\", but got \"{any}\"", .{ expected, a });
                    }

                    return error.TestExpectedError;
                } else |e| {
                    if (e != expected) {
                        if (self.printColor) {
                            try self.handleTestError("Expected " ++ White ++ "\"{any}\"" ++ Reset ++ ", but got \"{any}\"" ++ Reset, .{ actual, e });
                        } else {
                            try self.handleTestError("Expected \"{any}\", but got \"{any}\"", .{ actual, e });
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

// Windows-specific PDB-based stack trace that bypasses std.fs.selfExeDirPath
// (which fails under Wine).  Loads the PDB file directly using GetModuleFileNameW.
// Returns error if the PDB cannot be found or parsed; caller should fall back.
fn printWindowsPdbTrace(
    alloc: std.mem.Allocator,
    failure: *TestFailure,
    out_stream: anytype,
    first_out: *bool,
    printColor: bool,
    addr_buf: []const usize,
) !void {
    const windows = std.os.windows;

    // Get image base from the PEB.
    const image_base = @intFromPtr(windows.peb().ImageBaseAddress);

    // Read SizeOfImage from the PE optional header.
    // Layout: DOS header → PE offset at +0x3c → PE signature (4) + COFF header (20)
    //         → Optional header.  For PE32+, size_of_image is at optional header + 56.
    const pe_offset: usize = @as(*align(1) const u32, @ptrFromInt(image_base + 0x3c)).*;
    const size_of_image: usize = @as(*align(1) const u32, @ptrFromInt(image_base + pe_offset + 4 + 20 + 56)).*;

    // Build a Coff view of the in-memory (loaded) image.
    const image_slice = @as([*]const u8, @ptrFromInt(image_base))[0..size_of_image];
    var coff_obj = try std.coff.Coff.init(image_slice, true);

    // Pull the PDB filename (relative path like "unit_tests.pdb") from the debug directory.
    const pdb_filename = try coff_obj.getPdbPath() orelse return error.MissingDebugInfo;

    // GetModuleFileNameW works under Wine; selfExeDirPath does not (realpathW fails).
    var exe_path_w: [windows.PATH_MAX_WIDE:0]u16 = undefined;
    const exe_path_w_len = windows.kernel32.GetModuleFileNameW(
        null,
        &exe_path_w,
        windows.PATH_MAX_WIDE,
    );
    if (exe_path_w_len == 0) return error.Unexpected;

    var exe_path_utf8: [std.fs.max_path_bytes]u8 = undefined;
    const exe_path_len = std.unicode.wtf16LeToWtf8(&exe_path_utf8, exe_path_w[0..exe_path_w_len]);
    const exe_dir = std.fs.path.dirname(exe_path_utf8[0..exe_path_len]) orelse return error.Unexpected;

    // Build the full PDB path and open it.
    var pdb_path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const pdb_path = try std.fmt.bufPrint(&pdb_path_buf, "{s}\\{s}", .{ exe_dir, pdb_filename });

    var pdb_obj = try std.debug.Pdb.init(alloc, pdb_path);
    defer pdb_obj.deinit();

    try pdb_obj.parseInfoStream();

    // Verify GUID + age so we know this PDB matches the binary.
    if (!std.mem.eql(u8, &coff_obj.guid, &pdb_obj.guid) or coff_obj.age != pdb_obj.age)
        return error.InvalidDebugInfo;

    try pdb_obj.parseDbiStream();

    // Section headers are needed to translate virtual addresses to PDB offsets.
    const section_headers = try coff_obj.getSectionHeadersAlloc(alloc);
    defer alloc.free(section_headers);

    for (addr_buf) |addr| {
        // Subtract 1 to get the call-site address (same as writeStackTraceWindows).
        const address = addr -| 1;
        if (address < image_base) continue;
        const relocated: usize = address - image_base;

        // Walk PDB section contributions to find which module owns this address.
        var match_section: *const std.coff.SectionHeader = undefined;
        const mod_index: usize = for (pdb_obj.sect_contribs) |sc| {
            if (sc.section == 0 or sc.section > section_headers.len) continue;
            match_section = &section_headers[sc.section - 1];
            const va_start: usize = @as(usize, match_section.virtual_address) + sc.offset;
            const va_end: usize = va_start + sc.size;
            if (relocated >= va_start and relocated < va_end) break sc.module_index;
        } else continue; // not in any contribution → skip (system/stub frames)

        const module = (try pdb_obj.getModule(mod_index)) orelse continue;

        // Offset within the section used for both symbol and line lookups.
        const sec_offset: u64 = relocated - match_section.virtual_address;

        // Get line info; allocates file_name with pdb_obj's allocator (== alloc).
        const li = pdb_obj.getLineNumberInfo(module, sec_offset) catch continue;
        defer alloc.free(li.file_name);

        // Apply testz framework filters.
        if (std.mem.endsWith(u8, li.file_name, "__testz.zig")) continue;
        if (std.mem.endsWith(u8, li.file_name, "/testz.zig")) continue;
        if (std.mem.endsWith(u8, li.file_name, "\\testz.zig")) continue;
        // Skip Zig runtime startup frames (Windows equivalent of posixCallMainAndExit).
        if (std.mem.endsWith(u8, li.file_name, "/start.zig")) continue;
        if (std.mem.endsWith(u8, li.file_name, "\\start.zig")) continue;

        // Skip the main entry point by symbol name.
        const sym_name = pdb_obj.getSymbolName(module, sec_offset) orelse "";
        if (std.mem.eql(u8, sym_name, "main")) continue;

        if (printColor) {
            std.fmt.format(out_stream, "\n{s}:" ++ White ++ "{d}" ++ Reset ++ ":{d}:\n", .{ li.file_name, li.line, li.column }) catch break;
        } else {
            std.fmt.format(out_stream, "\n{s}:{d}:{d}:\n", .{ li.file_name, li.line, li.column }) catch break;
        }

        if (first_out.*) {
            failure.lineNo = li.line;
            first_out.* = false;
        }

        // Source-file context display; may fail on Wine since paths are Linux-style.
        printLinesFromFileAnyOs(out_stream, li, 3, printColor) catch {};
    }
}

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
    var stderr_buffer: [4096]u8 = undefined;
    var stderr_writer = std.fs.File.stderr().writer(&stderr_buffer);
    const stderr = &stderr_writer.interface;

    // nosuspend {
    if (comptime builtin.target.cpu.arch.isWasm()) {
        if (native_os == .wasi) {
            stderr.print("Unable to dump stack trace: not implemented for Wasm\n", .{}) catch return;
        }
        return;
    }

    if (builtin.strip_debug_info) {
        stderr.print("Unable to dump stack trace: debug info stripped\n", .{}) catch return;
        return;
    }
    var trace: StringBuilder = .{};
    // Preallocate some space for the stack trace.
    try trace.ensureTotalCapacity(failure.alloc, 2048);
    const out_stream = trace.writer(failure.alloc);
    defer trace.deinit(failure.alloc);
    var first = true;

    if (native_os == .windows) {
        // On Windows, walk the stack and resolve via PDB using our Wine-compatible helper.
        // getSelfDebugInfo() is intentionally NOT called here: it uses selfExeDirPath which
        // calls realpathW / GetFinalPathNameByHandle, and that fails under Wine.
        var context: std.debug.ThreadContext = undefined;
        std.debug.assert(std.debug.getContext(&context));

        var addr_buf: [256]usize = undefined;
        const n = std.debug.walkStackWindows(addr_buf[0..], &context);

        printWindowsPdbTrace(failure.alloc, failure, out_stream, &first, printColor, addr_buf[0..n]) catch {};
    } else {
        const debug_info = std.debug.getSelfDebugInfo() catch |err| {
            stderr.print("Unable to dump stack trace: Unable to open debug info: {s}\n", .{@errorName(err)}) catch return;
            return;
        };

        var context: std.debug.ThreadContext = undefined;
        const has_context = std.debug.getContext(&context);

        var it = (if (has_context) blk: {
            break :blk std.debug.StackIterator.initWithContext(null, debug_info, &context) catch null;
        } else null) orelse std.debug.StackIterator.init(null, null);
        defer it.deinit();

        while (it.next()) |return_address| {
            const module = debug_info.getModuleForAddress(return_address) catch {
                break;
            };

            const symbol_info = module.getSymbolAtAddress(debug_info.allocator, return_address) catch {
                break;
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

            if (line_info) |li| {
                printLinesFromFileAnyOs(out_stream, li, 3, printColor) catch {};
            }
        }
    }

    if (first) {
        std.fmt.format(out_stream, "No printable stack frames.", .{}) catch {};
    }

    failure.stackTrace = try trace.toOwnedSlice(failure.alloc);
}
