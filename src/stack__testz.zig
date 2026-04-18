// Stack trace printing using the Zig 0.16 SelfInfo API.
// Captures the current call stack, filters out testz-internal frames,
// and stores the formatted result in failure.stackTrace.
const std = @import("std");

const builtin = @import("builtin");

const core = @import("./core.zig");
const TestFailure = core.TestFailure;

const highlight_ansi = @import("highlight_ansi");

const White = "\x1b[97m";
const Green = "\x1b[32m";
const Bold = "\x1b[1m";
const Dim = "\x1b[2m";
const Reset = "\x1b[0m";

const CONTEXT_LINES = 3;

// Print CONTEXT_LINES lines before and after loc.line, with line numbers and
// an arrow on the target line. The caret is printed below the target line at
// loc.column. Errors are silently ignored.
fn printSourceContext(alloc: std.mem.Allocator, io: std.Io, w: *std.Io.Writer, loc: std.debug.SourceLocation, printColor: bool) void {
    const target: usize = loc.line;
    const start: usize = if (target > CONTEXT_LINES) target - CONTEXT_LINES else 1;
    const end: usize = target + CONTEXT_LINES;

    // Width needed for the largest line number in the range.
    var width: usize = 1;
    var tmp = end;
    while (tmp >= 10) : (tmp /= 10) width += 1;

    const cwd: std.Io.Dir = .cwd();
    var file = cwd.openFile(io, loc.file_name, .{}) catch return;
    defer file.close(io);

    // Read the whole file into memory so we can index by line number.
    var file_buf: [256]u8 = undefined;
    var file_reader: std.Io.File.Reader = .init(file, io, &file_buf);
    const contents = file_reader.interface.allocRemaining(alloc, .unlimited) catch return;
    defer alloc.free(contents);

    // Highlight with ANSI codes when color is enabled; fall back to plain text.
    // `highlighted` is null on error or when color is off, so we never double-free `contents`.
    const highlighted = if (printColor) highlight_ansi.highlightZigAnsi(alloc, contents) catch null else null;
    defer if (highlighted) |h| alloc.free(h);
    const display_contents = highlighted orelse contents;

    // Split into lines (without the trailing \n).
    var lines: std.ArrayList([]const u8) = .empty;
    defer lines.deinit(alloc);
    var it = std.mem.splitScalar(u8, display_contents, '\n');
    while (it.next()) |line| {
        lines.append(alloc, line) catch return;
    }

    const first = start - 1; // 0-indexed
    const last = @min(end, lines.items.len); // exclusive upper bound (1-indexed end)

    var line_index: usize = first;
    while (line_index < last) : (line_index += 1) {
        const line_no = line_index + 1; // 1-indexed
        const is_target = (line_no == target);
        const line_text = lines.items[line_index];

        // Right-align the line number within `width` columns.
        var num_buf: [20]u8 = undefined;
        const num_str = std.fmt.bufPrint(&num_buf, "{d}", .{line_no}) catch return;
        const pad = width - num_str.len;

        if (is_target) {
            if (printColor) w.writeAll(Green) catch return;
            w.writeAll("> ") catch return;
            w.splatByteAll(' ', pad) catch return;
            w.writeAll(num_str) catch return;
            if (printColor) w.writeAll(Reset) catch return;
            w.writeAll(" | ") catch return;
        } else {
            if (printColor) w.writeAll(Dim) catch return;
            w.writeAll("  ") catch return;
            w.splatByteAll(' ', pad) catch return;
            w.writeAll(num_str) catch return;
            w.writeAll(" |") catch return;
            if (printColor) w.writeAll(Reset) catch return;
            w.writeAll(" ") catch return;
        }

        w.writeAll(line_text) catch return;
        w.writeByte('\n') catch return;

        // After the target line, print the caret.
        if (is_target and loc.column > 0) {
            // Prefix width: "  {pad}{num} | " = 2 + width + 3 = width + 5
            const prefix_len = width + 5;
            const col_offset = @as(usize, @intCast(loc.column - 1));
            w.splatByteAll(' ', prefix_len + col_offset) catch return;
            if (printColor) {
                w.writeAll(Green ++ "^" ++ Reset) catch return;
            } else {
                w.writeByte('^') catch return;
            }
            w.writeByte('\n') catch return;
        }
    }
}

pub fn printStackTrace(failure: *TestFailure, printColor: bool) !void {
    if (comptime builtin.target.cpu.arch.isWasm()) return;

    if (builtin.strip_debug_info) {
        failure.stackTrace = try failure.alloc.dupe(u8, "Unable to dump stack trace: debug info stripped\n");
        return;
    }

    const debug_info = std.debug.getSelfDebugInfo() catch {
        failure.stackTrace = try failure.alloc.dupe(u8, "Unable to dump stack trace: no debug info\n");
        return;
    };

    // Capture raw return addresses into a fixed buffer.
    var addr_buf: [64]usize = undefined;
    const trace = std.debug.captureCurrentStackTrace(.{
        .first_address = @returnAddress(),
    }, &addr_buf);

    var out: std.Io.Writer.Allocating = try .initCapacity(failure.alloc, 4096);
    defer out.deinit();
    const w = &out.writer;

    // Arena for symbol/location strings; freed at the end of this function.
    var text_arena = std.heap.ArenaAllocator.init(failure.alloc);
    defer text_arena.deinit();
    const arena = text_arena.allocator();

    const io = std.Io.Threaded.global_single_threaded.io();

    var symbols: std.ArrayList(std.debug.Symbol) = .empty;

    for (trace.return_addresses) |addr| {
        symbols.clearRetainingCapacity();
        debug_info.getSymbols(io, arena, arena, addr, false, &symbols) catch continue;

        for (symbols.items) |sym| {
            const loc = sym.source_location orelse continue;

            // Skip testz framework and runtime frames.
            if (std.mem.endsWith(u8, loc.file_name, "__testz.zig")) continue;
            if (std.mem.endsWith(u8, loc.file_name, "/testz.zig")) continue;
            if (std.mem.indexOf(u8, loc.file_name, "/lib/std/") != null) continue;
            if (sym.name) |n| if (std.mem.eql(u8, n, "main")) continue;

            // Record the first non-framework line for the failure summary.
            if (failure.lineNo == 0) failure.lineNo = loc.line;

            if (printColor) {
                w.print("\n{s}:{s}{d}{s}:{d}:\n", .{ loc.file_name, White, loc.line, Reset, loc.column }) catch break;
            } else {
                w.print("\n{s}:{d}:{d}:\n", .{ loc.file_name, loc.line, loc.column }) catch break;
            }
            printSourceContext(arena, io, w, loc, printColor);
        }
    }

    if (out.writer.end == 0) {
        w.writeAll("No printable stack frames.\n") catch {};
    }

    failure.stackTrace = try failure.alloc.dupe(u8, out.writer.buffer[0..out.writer.end]);
}
