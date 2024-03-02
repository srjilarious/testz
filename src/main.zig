const std = @import("std");
const testz = @import("testz");

fn failTest2() !void {
    const mem = try std.heap.page_allocator.alloc(u8, 10);
    defer std.heap.page_allocator.free(mem);
    try testz.expectTrue(true);
    try testz.expectTrue(false);
}

fn failTest() !void {
    const mem = try std.heap.page_allocator.alloc(u8, 10);
    defer std.heap.page_allocator.free(mem);
    try testz.expectEqual(true, false);
}

fn successTest() !void {
    try testz.expectEqual(true, true);
    try testz.expectTrue(true);
}

fn skip_Test() !void {
    // nothing to see here.
}

pub fn main() !void {
    _ = testz.runTests(&[_]testz.TestFuncInfo{
        .{ .func = failTest, .name = "failTest", .skip = false },
        .{ .func = skip_Test, .name = "skip_Test", .skip = true },
        .{ .func = failTest2, .name = "failTest2", .skip = false },
        .{ .func = successTest, .name = "successTest", .skip = false },
    }, true);
}
