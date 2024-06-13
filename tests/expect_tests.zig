const std = @import("std");
const testz = @import("testz");
const TestFunc = testz.TestFunc;

// fn runInternalTest(func: TestFunc) !void {
//     testz.runTests(.{ func }, .{});
// }

pub fn expectEqualFailTest() !void {
    try testz.expectEqual(10, 20);
}

pub fn expectNotEqualFailTest() !void {
    try testz.expectNotEqual(10, 10);
}

pub fn expectEqualStrFailTest() !void {
    try testz.expectEqualStr("hello", "world");
}

pub fn expectNotEqualStrFailTest() !void {
    try testz.expectNotEqualStr("hello", "hello");
}

pub fn expectTrueFailTest() !void {
    try testz.expectTrue(false);
}

pub fn expectFalseFailTest() !void {
    try testz.expectFalse(true);
}
