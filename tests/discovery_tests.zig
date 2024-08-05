const std = @import("std");
const testz = @import("testz");
const TestFuncInfo = testz.TestFuncInfo;
const TestContext = testz.TestContext;
const Printer = testz.Printer;

const mod1 = struct {
    pub fn func1() !void {}

    pub fn func2() !void {}
};

const mod2 = struct {
    pub fn func1() !void {}

    pub fn func2() !void {}

    pub fn func3() !void {}
};

const TestsSet1 = testz.discoverTests(.{
    testz.Group{ .name = "Mod 1 tests", .tag = "mod1", .mod = mod1 },
}, .{});

pub fn testBasicTestDiscovery() !void {
    try testz.expectEqual(TestsSet1.len, 2);
}

const TestsSet2 = testz.discoverTests(.{
    testz.GroupList{ .name = "Mod tests", .tag = "mod", .mods = &.{ mod1, mod2 } },
}, .{});

pub fn testGroupListTestDiscovery() !void {
    try testz.expectEqual(TestsSet2.len, 5);
}
