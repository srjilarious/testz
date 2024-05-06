const std = @import("std");

const StrArrayList = std.ArrayList([]const u8);

pub fn tokenizeShellString(alloc: std.mem.Allocator, input: []const u8) ![][]const u8 {
    var tokens = StrArrayList.init(alloc);
    defer tokens.deinit();

    var in_single_quote = false;
    var in_double_quote = false;
    var start: usize = 0;
    var i: usize = 0;

    while (i < input.len) {
        switch (input[i]) {
            '\'' => {
                if (in_single_quote) {
                    try tokens.append(input[start..i]);
                }

                i += 1;

                if (!in_double_quote) {
                    in_single_quote = !in_single_quote;
                    start = i; // Update start to not include the quote
                }
            },
            '"' => {
                if (in_double_quote) {
                    try tokens.append(input[start..i]);
                }

                i += 1;

                if (!in_single_quote) {
                    in_double_quote = !in_double_quote;
                    start = i; // Update start to not include the quote
                }
            },
            ' ' => {
                if (!in_single_quote and !in_double_quote) {
                    if (i != start) { // Avoid empty tokens
                        try tokens.append(input[start..i]);
                    }
                    start = i + 1; // Update start to after the space
                }
                i += 1;
            },
            else => i += 1,
        }
    }

    // Append the last token if there's any leftovers not followed by a space
    if (i != start) {
        try tokens.append(input[start..i]);
    }

    return tokens.toOwnedSlice();
}

pub fn cStrToSlice(c_str: [*:0]const u8) []const u8 {
    const length = std.mem.len(c_str);
    return c_str[0..length];
}
