// zig fmt: off
const std = @import("std");
const testz = @import("testz");
//const zargs = @import("zargunaught");

//const Option = zargs.Option;

const DiscoveredTests = testz.discoverTests(.{ 
    testz.Group{ .name = "Expect Tests", .tag = "expect", .mod = @import("./expect_tests.zig") }, 
    testz.Group{ .name = "Misc Tests", .tag = "misc", .mod = @import("./misc_tests.zig") } 
});

pub fn main() !void {
    try testz.testzRunner(DiscoveredTests);
    // var parser = try zargs.ArgParser.init(
    //     std.heap.page_allocator, .{ 
    //         .name = "Testz tests program", 
    //         .description = "Tests for the testz framework.", 
    //         .opts = &[_]Option{
    //             Option{ .longName = "verbose", .shortName = "v", .description = "Verbose output", .maxNumParams = 0 },
    //             Option{ .longName = "stack_trace", .shortName = "s", .description = "Print stack traces on errors", .maxNumParams = 0 },
    //         } 
    //     });
    // defer parser.deinit();
    //
    // var args = parser.parse() catch |err| {
    //     std.debug.print("Error parsing args: {any}\n", .{err});
    //     return;
    // };
    // defer args.deinit();
    //
    // const verbose = args.hasOption("verbose");
    // const printStackTrace = args.hasOption("stack_trace");
    //
    // _ = try testz.runTests(
    //     DiscoveredTests,
    //     .{
    //         .verbose = verbose,
    //         // .allowFilters = &[_][]const u8{
    //         //     "misc", 
    //         //     "successTest"
    //         // },
    //         .printStackTraceOnFail = printStackTrace
    //     }
    // );
}
