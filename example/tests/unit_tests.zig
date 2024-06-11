// Example main unit test runner using testz.
const std = @import("std");
const add = @import("example").add;
const testz = @import("testz");

const LocalExampleTests = struct {
    fn helpFunction() bool {
        return true;
    }

    pub fn shouldPassTest() !void {
        try testz.expectTrue(helpFunction());
        try testz.expectEqual(add(10, 20), 30);
    }

    pub fn skip_notReadyTest() !void {
        try testz.failWith("This should never get hit, since we marked this test skip.");
    }

    pub fn gonnaFailTest() !void {
        try testz.expectEqual(add(1, 2), 12);
    }
};

const Tests = testz.discoverTests(.{
    // Rather than a local struct, we could simply import a module with these top-level functions.
    testz.Group{ .name = "Example tests", .tag = "example", .mod = LocalExampleTests },
}, .{});

pub fn main() !void {
    try testz.testzRunner(Tests);
}
