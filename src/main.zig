const std = @import("std");
const testz = @import("testz");

fn myTest() !void {
    const mem = try std.heap.page_allocator.alloc(u8, 10);
    defer std.heap.page_allocator.free(mem);
    try testz.expectEqual(true, false);
}

pub fn main() !void {
    _ = testz.runTests(&[_]testz.TestFuncInfo{.{ .func = myTest, .name = "myTest", .skip = false }}, true);
}
