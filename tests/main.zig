const std = @import("std");
const testz = @import("testz");

const DiscoveredTests = testz.discoverTests(.{
    testz.Group{ .name = "Expect Tests", .tag = "expect", .mod = @import("./expect_tests.zig") },
    testz.Group{ .name = "Misc Tests", .tag = "misc", .mod = @import("./misc_tests.zig") },
    testz.Group{ .name = "Discovery Tests", .tag = "discovery", .mod = @import("./discovery_tests.zig") },
    testz.Group{ .name = "Output Tests", .tag = "output", .mod = @import("./output_tests.zig") },
    testz.Group{ .name = "Highlight Tests", .tag = "highlight", .mod = @import("./highlight_tests.zig") },
}, .{});

pub fn main(init: std.process.Init) !void {
    try testz.testzRunner(DiscoveredTests, init.minimal.args);
}
