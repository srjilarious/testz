// Zig syntax highlighting for ANSI terminal output.
// Adapted from zkdocs/src/highlight.zig — drops JSON support and HTML span
// wrapping, emitting ANSI escape codes instead.
const std = @import("std");
const ts = @import("tree_sitter");
const ts_zig = @import("tree-sitter-zig");

const highlights_zig = @embedFile("assets/highlights.scm");

// ANSI color codes used for each syntax category.
pub const Keyword  = "\x1b[35m";  // magenta
pub const Function = "\x1b[94m";  // bright blue
pub const Type     = "\x1b[36m";  // cyan
pub const Constant = "\x1b[96m";  // bright cyan
pub const String   = "\x1b[32m";  // green
pub const Number   = "\x1b[93m";  // yellow
pub const Comment  = "\x1b[90m";  // dark gray
pub const Operator = "\x1b[97m";  // bright white
pub const Reset    = "\x1b[0m";

const CaptureRange = struct {
    start: u32,
    end: u32,
    ansi_code: []const u8,
    pattern_index: u16,
};

/// Highlight Zig source with ANSI terminal colors.
/// Returns an owned slice the caller must free with `allocator`.
/// Falls back to a plain copy of `source` on any tree-sitter error.
pub fn highlightZigAnsi(allocator: std.mem.Allocator, source: []const u8) ![]const u8 {
    const parser = ts.Parser.create();
    defer parser.destroy();

    const lang: *const ts.Language = @ptrCast(@alignCast(ts_zig.language()));
    try parser.setLanguage(lang);

    const tree = parser.parseString(source, null) orelse {
        return allocator.dupe(u8, source);
    };
    defer tree.destroy();

    var error_offset: u32 = 0;
    const query = ts.Query.create(lang, highlights_zig, &error_offset) catch {
        return allocator.dupe(u8, source);
    };
    defer query.destroy();

    const cursor = ts.QueryCursor.create();
    defer cursor.destroy();
    cursor.exec(query, tree.rootNode());

    var ranges: std.ArrayList(CaptureRange) = .empty;
    defer ranges.deinit(allocator);

    while (cursor.nextCapture()) |tup| {
        const ci = tup[0];
        const m = tup[1];
        if (ci >= m.captures.len) continue;
        const cap = m.captures[ci];
        const name = query.captureNameForId(cap.index) orelse continue;
        const ansi_code = ansiCode(name) orelse continue;
        try ranges.append(allocator, .{
            .start = cap.node.startByte(),
            .end = cap.node.endByte(),
            .ansi_code = ansi_code,
            .pattern_index = m.pattern_index,
        });
    }

    std.mem.sort(CaptureRange, ranges.items, {}, struct {
        fn lt(_: void, a: CaptureRange, b: CaptureRange) bool {
            if (a.start != b.start) return a.start < b.start;
            return a.pattern_index < b.pattern_index;
        }
    }.lt);

    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);

    const src_len: u32 = @intCast(source.len);
    var pos: u32 = 0;
    var ri: usize = 0;

    while (pos < src_len) {
        // Skip any ranges that end before our current position.
        while (ri < ranges.items.len and ranges.items[ri].end <= pos) ri += 1;

        const next_start: u32 = if (ri < ranges.items.len) ranges.items[ri].start else src_len;

        if (next_start > pos) {
            // Plain text up to the next highlighted range.
            try out.appendSlice(allocator, source[pos..next_start]);
            pos = next_start;
        } else if (ri < ranges.items.len) {
            // Emit the highlighted token.
            const r = ranges.items[ri];
            ri += 1;
            try out.appendSlice(allocator, r.ansi_code);
            try out.appendSlice(allocator, source[r.start..r.end]);
            try out.appendSlice(allocator, Reset);
            pos = r.end;
            // Skip any ranges that now fall behind our new position.
            while (ri < ranges.items.len and ranges.items[ri].start < pos) ri += 1;
        } else {
            break;
        }
    }

    return out.toOwnedSlice(allocator);
}

fn ansiCode(name: []const u8) ?[]const u8 {
    if (std.mem.startsWith(u8, name, "keyword")) return Keyword;
    if (std.mem.startsWith(u8, name, "function")) return Function;
    if (std.mem.startsWith(u8, name, "type")) return Type;
    if (std.mem.startsWith(u8, name, "constant")) return Constant;
    if (std.mem.startsWith(u8, name, "string") or
        std.mem.eql(u8, name, "character")) return String;
    if (std.mem.startsWith(u8, name, "number")) return Number;
    if (std.mem.eql(u8, name, "boolean")) return Constant;
    if (std.mem.startsWith(u8, name, "comment")) return Comment;
    if (std.mem.eql(u8, name, "operator")) return Operator;
    return null;
}
