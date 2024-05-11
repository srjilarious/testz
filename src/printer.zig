// zig fmt: off
const std = @import("std");

const FilePrinterData = struct {
    file: std.fs.File,
    bufferWriter: std.io.BufferedWriter(4096, std.fs.File.Writer)
};

const ArrayPrinterData = struct {
    array: std.ArrayList(u8),
    bufferWriter: std.io.BufferedWriter(4096, std.ArrayList(u8).Writer)
};

// An adapter for printing either to an ArrayList or to a File like stdout.
pub const Printer = union(enum) {
    file: FilePrinterData,
    array: ArrayPrinterData,
    
    pub fn stdout() Printer {
        var f: FilePrinterData = .{ 
            .file = std.io.getStdOut(),
            .bufferWriter = undefined
        };
        f.bufferWriter = std.io.bufferedWriter(f.file.writer());
        return .{.file = f};
    }

    pub fn memory(alloc: std.mem.Allocator) Printer {
        var a: ArrayPrinterData = .{
            .array = std.ArrayList(u8).init(alloc),
            .bufferWriter = undefined,
        };

        a.bufferWriter = std.io.bufferedWriter(a.array.writer());
        return .{.array = a};
    }

    pub fn deinit(self: *Printer) void {
        switch(self.*) {
            .array => |arr| { arr.array.deinit(); },
            else => {}
        }
    }

    pub fn print(self: *Printer, comptime format: []const u8, args: anytype) anyerror!void
    {
        switch(self.*) {
            .array => |_| try self.array.array.writer().print(format, args),
            .file => |_| try self.file.bufferWriter.writer().print(format, args),
        }
    }

    pub fn flush(self: *Printer) anyerror!void
    {
        switch(self.*) {
            .array => |_| {}, // try self.array.bufferWriter.flush(),
            .file => |_| try self.file.bufferWriter.flush(),
        }
    }
};
