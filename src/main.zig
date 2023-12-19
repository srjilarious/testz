const std = @import("std");
const testz = @import("testz");

fn myTest() !void {
    try testz.expectEqual(true, false);
}

pub fn main() !void {
    _ = testz.runTests(&[_]testz.TestFuncInfo{.{ .func = myTest, .name = "myTest", .skip = false }}, true);
}
