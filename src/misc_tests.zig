const std = @import("std");
const testz = @import("testz");

pub fn allowNonTestzErrorsTest() !void {
    const mem = try std.heap.page_allocator.alloc(u8, 10);
    defer std.heap.page_allocator.free(mem);
    try testz.expectEqual(true, true);
}

pub fn alwaysFailTest() !void {
    try testz.fail();
}

pub fn successTest() !void {
    try testz.expectEqual(12, 12);
    // try testz.expectEqual("hello", "hello");
    try testz.expectNotEqual(10, 20);
    // try testz.expectNotEqualStr("hello", "world");
    try testz.expectTrue(true);
    try testz.expectFalse(false);
}

pub fn skip_Test() !void {
    // nothing to see here.
}