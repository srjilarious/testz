const std = @import("std");
const testz = @import("testz");

pub fn group1Test() !void {
    _ = try testz.expectTrue(true);
}
