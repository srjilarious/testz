const std = @import("std");
const testz = @import("testz");
const highlight_ansi = @import("highlight_ansi");

const Keyword  = highlight_ansi.Keyword;
const Function = highlight_ansi.Function;
const Type     = highlight_ansi.Type;
const Constant = highlight_ansi.Constant;
const String   = highlight_ansi.String;
const Number   = highlight_ansi.Number;
const Comment  = highlight_ansi.Comment;
const Reset    = highlight_ansi.Reset;

// Helper: returns true when `needle` appears inside `haystack`.
fn contains(haystack: []const u8, needle: []const u8) bool {
    return std.mem.indexOf(u8, haystack, needle) != null;
}

pub fn keywordsHighlightedTest() !void {
    const alloc = std.heap.page_allocator;
    const source = "const x: u32 = 42;";
    const result = try highlight_ansi.highlightZigAnsi(alloc, source);
    defer alloc.free(result);

    // Output must contain ANSI escape codes at all.
    try testz.expectTrue(contains(result, "\x1b["));
    // "const" is a keyword — must be wrapped in Keyword color + Reset.
    try testz.expectTrue(contains(result, Keyword ++ "const" ++ Reset));
    // "u32" is a builtin type — must be wrapped in Type color + Reset.
    try testz.expectTrue(contains(result, Type ++ "u32" ++ Reset));
    // "42" is an integer literal — must be wrapped in Number color + Reset.
    try testz.expectTrue(contains(result, Number ++ "42" ++ Reset));
    // Original text must still be present (just with color codes around tokens).
    try testz.expectTrue(contains(result, "x"));
}

pub fn commentsHighlightedTest() !void {
    const alloc = std.heap.page_allocator;
    const source = "// a comment\nconst y = 1;";
    const result = try highlight_ansi.highlightZigAnsi(alloc, source);
    defer alloc.free(result);

    try testz.expectTrue(contains(result, Comment ++ "// a comment" ++ Reset));
    try testz.expectTrue(contains(result, Keyword ++ "const" ++ Reset));
}

pub fn stringsHighlightedTest() !void {
    const alloc = std.heap.page_allocator;
    const source =
        \\const s = "hello";
    ;
    const result = try highlight_ansi.highlightZigAnsi(alloc, source);
    defer alloc.free(result);

    try testz.expectTrue(contains(result, String ++ "\"hello\"" ++ Reset));
}

pub fn builtinFunctionHighlightedTest() !void {
    const alloc = std.heap.page_allocator;
    const source = "const n = @intCast(x);";
    const result = try highlight_ansi.highlightZigAnsi(alloc, source);
    defer alloc.free(result);

    // @intCast is a builtin function — captured as function.builtin.
    try testz.expectTrue(contains(result, Function ++ "@intCast" ++ Reset));
}

pub fn plainFallbackOnEmptyTest() !void {
    const alloc = std.heap.page_allocator;
    // Empty source should not error — just returns an empty string.
    const result = try highlight_ansi.highlightZigAnsi(alloc, "");
    defer alloc.free(result);
    try testz.expectEqualStr(result, "");
}
