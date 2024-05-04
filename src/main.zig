// zig fmt: off
const std = @import("std");
const testz = @import("testz");

const DiscoveredTests = testz.discoverTests(.{ 
    testz.Group{ .name = "Expect Tests", .mod = @import("./expect_tests.zig") }, 
    testz.Group{ .name = "Misc Tests", .mod = @import("./misc_tests.zig") } 
});

pub fn main() !void {
    const verbose = if (std.os.argv.len > 1 and std.mem.eql(u8, "verbose", std.mem.span(std.os.argv[1]))) true else false;
    var filters: [1][]const u8 = .{"Misc Tests"};
    const filters2: [][]const u8 = filters[0..];
    _ = try testz.runTests(DiscoveredTests, .{ .verbose = verbose, .allowFilters = filters2});
}
