const std = @import("std");
const io = std.io;

const builtin = @import("builtin");
const native_os = builtin.os.tag;

const core = @import("./core.zig");
const TestFailure = core.TestFailure;
const StringBuilder = core.StringBuilder;

const printStackTrace = @import("./stack__testz.zig").printStackTrace;

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
