const std = @import("std");

pub const StringBuilder = std.ArrayList(u8);

pub const TestFunc = *const fn () anyerror!void;

pub const TestFuncInfo = struct {
    func: TestFunc,
    name: []const u8,
    group: TestGroup,
    skip: bool = false,
};

// Unpacked information from Group, not counting the module.
// This is stored along with each test, since that was much easier
// to get working in comptime than creating a hierarchy of objects.
pub const TestGroup = struct {
    name: ?[]const u8,
    tag: []const u8,
};

// Struct for how a module can be passed in and associated as a group.
pub const Group = struct {
    name: []const u8,
    // The string for filtering on.
    tag: []const u8,
    mod: type,
};

// Struct for how a list of modules can be passed in and associated as a group.
pub const GroupList = struct {
    name: []const u8,
    // The string for filtering on.
    tag: []const u8,
    mods: []const type,
};

// A group as used at runtime.
pub const TestFuncGroup = struct {
    name: []const u8,
    tests: std.ArrayList(TestFuncInfo),
    alloc: std.mem.Allocator,

    pub fn init(name: []const u8, alloc: std.mem.Allocator) TestFuncGroup {
        return .{ .name = name, .tests = .{}, .alloc = alloc };
    }

    pub fn deinit(self: *TestFuncGroup) void {
        self.tests.deinit(self.alloc);
    }
};

pub const TestFuncMap = std.StringHashMap(TestFuncGroup);

pub const TestFailure = struct {
    testName: []const u8,
    lineNo: usize,
    errorMessage: ?[]const u8,
    stackTrace: ?[]const u8,
    alloc: std.mem.Allocator,

    pub fn init(testName: []const u8, alloc: std.mem.Allocator) !TestFailure {
        return .{
            .alloc = alloc,
            .testName = try alloc.dupe(u8, testName),
            .lineNo = 0,
            .errorMessage = null,
            .stackTrace = null,
        };
    }

    pub fn deinit(self: *TestFailure) void {
        self.alloc.free(self.testName);
        if (self.errorMessage != null) self.alloc.free(self.errorMessage.?);
        if (self.stackTrace != null) self.alloc.free(self.stackTrace.?);
    }
};
