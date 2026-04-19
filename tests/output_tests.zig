const std = @import("std");
const testz = @import("testz");
const TestFuncInfo = testz.TestFuncInfo;

const runInternal = @import("./utils.zig").runInternal;
const runInternalMulti = @import("./utils.zig").runInternalMulti;

//-------------------------------------------------------------------------------------------------
// Verbose output tests
//-------------------------------------------------------------------------------------------------
fn verbosePassingInternal() !void {
    try testz.expectEqual(1, 1);
}

pub fn verbosePassingTest() !void {
    const expected: []const u8 =
        \\
        \\
        \\Running verbosePassing...✓ ( XX.XX ms)
        \\
        \\
        \\
        \\1 Passed, 0 Failed, 0 Skipped, 1 Total Tests ( XX.XX ms)
        \\
    ;

    try runInternal(.{
        .func = .{ .basic = verbosePassingInternal },
        .name = "verbosePassing",
        .group = .{ .name = "Default", .tag = "default" },
    }, expected, .{ .verbose = true });
}

//-------------------------------------------------------------------------------------------------
fn verboseFailingInternal() !void {
    try testz.fail();
}

pub fn verboseFailingTest() !void {
    const expected: []const u8 =
        \\
        \\
        \\Running verboseFailing...X ( XX.XX ms)
        \\
        \\
        \\FAIL verboseFailing: Test hit failure point.
        \\
        \\0 Passed, 1 Failed, 0 Skipped, 1 Total Tests ( XX.XX ms)
        \\
    ;

    try runInternal(.{
        .func = .{ .basic = verboseFailingInternal },
        .name = "verboseFailing",
        .group = .{ .name = "Default", .tag = "default" },
    }, expected, .{ .verbose = true });
}

//-------------------------------------------------------------------------------------------------
fn skip_verboseSkipInternal() !void {}

pub fn verboseSkipTest() !void {
    // f.name = "skip_verboseSkip" (16 chars), testPrintName = "verboseSkip" (11 chars)
    // verboseLength = 16, num = 16 - 11 = 5 extra dots, plus 2 hardcoded = 7 total
    const expected: []const u8 =
        \\
        \\
        \\Skipping verboseSkip.......↷
        \\
        \\
        \\
        \\0 Passed, 0 Failed, 1 Skipped, 1 Total Tests ( XX.XX ms)
        \\
    ;

    try runInternal(.{
        .func = .{ .basic = skip_verboseSkipInternal },
        .name = "skip_verboseSkip",
        .group = .{ .name = "Default", .tag = "default" },
    }, expected, .{ .verbose = true });
}

//-------------------------------------------------------------------------------------------------
// Filtered output tests
//-------------------------------------------------------------------------------------------------

fn filterAlphaPassFn() !void {}
fn filterBetaFailFn() !void {
    try testz.fail();
}

// Non-verbose: filter by tag "alpha" — betaFail is excluded, so no X or FAIL in output,
// and the summary shows only 1 Total Test (not 2).
pub fn filteredByTagTest() !void {
    const tests = &[_]TestFuncInfo{
        .{ .func = .{ .basic = filterAlphaPassFn }, .name = "alphaPass", .group = .{ .name = "Alpha", .tag = "alpha" } },
        .{ .func = .{ .basic = filterBetaFailFn }, .name = "betaFail", .group = .{ .name = "Beta", .tag = "beta" } },
    };
    const filters = &[_][]const u8{"alpha"};
    const expected: []const u8 =
        \\
        \\⋅
        \\
        \\1 Passed, 0 Failed, 0 Skipped, 1 Total Tests ( XX.XX ms)
        \\
    ;

    try runInternalMulti(tests, expected, .{ .allowFilters = filters });
}

//-------------------------------------------------------------------------------------------------
// Verbose + filtered: group header separator is printed for non-"default" tag groups.
// verboseLength = len("alphaPass") = 9, dashes = 9 + 22 = 31
pub fn verboseFilteredByTagTest() !void {
    const tests = &[_]TestFuncInfo{
        .{ .func = .{ .basic = filterAlphaPassFn }, .name = "alphaPass", .group = .{ .name = "Alpha", .tag = "alpha" } },
        .{ .func = .{ .basic = filterBetaFailFn }, .name = "betaFail", .group = .{ .name = "Beta", .tag = "beta" } },
    };
    const filters = &[_][]const u8{"alpha"};
    const expected: []const u8 =
        \\
        \\# -------------------------------
        \\# Alpha
        \\# -------------------------------
        \\Running alphaPass...✓ ( XX.XX ms)
        \\
        \\
        \\
        \\1 Passed, 0 Failed, 0 Skipped, 1 Total Tests ( XX.XX ms)
        \\
    ;

    try runInternalMulti(tests, expected, .{ .verbose = true, .allowFilters = filters });
}

//-------------------------------------------------------------------------------------------------
// Edge case: filter matches nothing — all tests excluded, counts are all zero.
pub fn filteredEmptyResultTest() !void {
    const tests = &[_]TestFuncInfo{
        .{ .func = .{ .basic = filterAlphaPassFn }, .name = "alphaPass", .group = .{ .name = "Alpha", .tag = "alpha" } },
        .{ .func = .{ .basic = filterBetaFailFn }, .name = "betaFail", .group = .{ .name = "Beta", .tag = "beta" } },
    };
    const filters = &[_][]const u8{"nonexistent"};
    const expected: []const u8 =
        \\
        \\
        \\
        \\0 Passed, 0 Failed, 0 Skipped, 0 Total Tests ( XX.XX ms)
        \\
    ;

    try runInternalMulti(tests, expected, .{ .allowFilters = filters });
}
