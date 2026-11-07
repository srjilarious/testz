const std = @import("std");

pub const TokenizeError = error{UnterminatedQuote} || std.mem.Allocator.Error;

/// The words split from a shell style string by `tokenizeShellString`.
/// `args` points into `text`, which this owns.
pub const ShellTokens = struct {
    args: []const []const u8,
    text: []u8,

    pub fn deinit(self: *const ShellTokens, alloc: std.mem.Allocator) void {
        alloc.free(self.args);
        alloc.free(self.text);
    }
};

/// Splits `input` into words the way a POSIX shell would, for the subset
/// that matters to argument parsing (no variables, globs or operators):
///
/// - Spaces, tabs and newlines separate words.
/// - 'single quotes' keep everything inside them literally.
/// - "double quotes" keep everything literally except `\"` and `\\`.
/// - Outside quotes, a backslash makes the next character literal.
/// - Quoted and unquoted parts next to each other form one word, so
///   `--name="a b"` is the single word `--name=a b`, and `""` is an
///   empty word.
pub fn tokenizeShellString(alloc: std.mem.Allocator, input: []const u8) TokenizeError!ShellTokens {
    // Removing quotes and backslashes only ever shrinks the text, so one
    // buffer the size of the input holds every word.
    const text = try alloc.alloc(u8, input.len);
    errdefer alloc.free(text);

    var words: std.ArrayList([]const u8) = .empty;
    defer words.deinit(alloc);

    const Quote = enum { none, single, double };
    var quote: Quote = .none;
    var len: usize = 0;
    var wordStart: usize = 0;
    // Set by any part of a word, including an empty pair of quotes.
    var inWord = false;

    var i: usize = 0;
    while (i < input.len) : (i += 1) {
        const c = input[i];
        switch (quote) {
            .single => {
                if (c == '\'') {
                    quote = .none;
                } else {
                    text[len] = c;
                    len += 1;
                }
            },
            .double => {
                if (c == '"') {
                    quote = .none;
                } else if (c == '\\' and i + 1 < input.len and (input[i + 1] == '"' or input[i + 1] == '\\')) {
                    i += 1;
                    text[len] = input[i];
                    len += 1;
                } else {
                    text[len] = c;
                    len += 1;
                }
            },
            .none => switch (c) {
                ' ', '\t', '\n' => {
                    if (inWord) {
                        try words.append(alloc, text[wordStart..len]);
                        inWord = false;
                    }
                },
                else => {
                    if (!inWord) {
                        inWord = true;
                        wordStart = len;
                    }

                    if (c == '\'') {
                        quote = .single;
                    } else if (c == '"') {
                        quote = .double;
                    } else if (c == '\\' and i + 1 < input.len) {
                        i += 1;
                        text[len] = input[i];
                        len += 1;
                    } else {
                        // Including a backslash at the very end, kept as is.
                        text[len] = c;
                        len += 1;
                    }
                },
            },
        }
    }

    if (quote != .none) return TokenizeError.UnterminatedQuote;

    if (inWord) {
        try words.append(alloc, text[wordStart..len]);
    }

    return .{ .args = try words.toOwnedSlice(alloc), .text = text };
}

pub fn cStrToSlice(c_str: [*:0]const u8) []const u8 {
    return std.mem.span(c_str);
}
