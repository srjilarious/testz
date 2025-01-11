// zig fmt: off
const std = @import("std");

pub const Color = enum {
    Reset,
    Black,
    Red,
    Green,
    Yellow,
    Blue,
    Magenta,
    Cyan,
    White,
    Gray,
    BrightRed,
    BrightGreen,
    BrightYellow,
    BrightBlue,
    BrightMagenta,
    BrightCyan,
    BrightWhite
};

pub const TextStyle = packed struct {
    dim: bool = false,
    bold: bool = false,
    underline: bool = false,
    italic: bool = false,

    pub fn none(self: TextStyle) bool {
        const val: u4 = @bitCast(self);
        return val == 0;
    }
};

pub const Style = struct {
    fg: Color,
    bg: Color,
    mod: TextStyle,

    pub fn reset(printer: Printer) !void {
        try printer.print("\x1b[0m", .{});
    }

    pub fn set(self: *const Style, printer: Printer) !void {
        if(!printer.supportsColor()) return;

        if(self.fg == .Reset or self.bg == .Reset or self.mod.none()) {
            try reset(printer);
        }
        
        if(self.mod.dim) {
            try printer.print("\x1b[2m", .{});
        }
        if(self.mod.bold) {
            try printer.print("\x1b[1m", .{});
        }
        if(self.mod.italic) {
            try printer.print("\x1b[3m", .{});
        }
        if(self.mod.underline) {
            try printer.print("\x1b[4m", .{});
        }

        switch(self.bg) 
        {
            .Black => try printer.print("\x1b[40m", .{}),
            .Red => try printer.print("\x1b[41m", .{}),
            .Green => try printer.print("\x1b[42m", .{}),
            .Yellow => try printer.print("\x1b[43m", .{}),
            .Blue => try printer.print("\x1b[44m", .{}),
            .Magenta => try printer.print("\x1b[45m", .{}),
            .Cyan => try printer.print("\x1b[46m", .{}),
            .White => try printer.print("\x1b[47m", .{}),
            .Gray => try printer.print("\x1b[100m", .{}),
            .BrightRed => try printer.print("\x1b[101m", .{}),
            .BrightGreen => try printer.print("\x1b[102m", .{}),
            .BrightYellow => try printer.print("\x1b[103m", .{}),
            .BrightBlue => try printer.print("\x1b[104m", .{}),
            .BrightMagenta => try printer.print("\x1b[105m", .{}),
            .BrightCyan => try printer.print("\x1b[106m", .{}),
            .BrightWhite => try printer.print("\x1b[107m", .{}),
            else => {},
        }

        switch(self.fg) 
        {
            .Black => try printer.print("\x1b[30m", .{}),
            .Red => try printer.print("\x1b[31m", .{}),
            .Green => try printer.print("\x1b[32m", .{}),
            .Yellow => try printer.print("\x1b[33m", .{}),
            .Blue => try printer.print("\x1b[34m", .{}),
            .Magenta => try printer.print("\x1b[35m", .{}),
            .Cyan => try printer.print("\x1b[36m", .{}),
            .White => try printer.print("\x1b[37m", .{}),
            .Gray => try printer.print("\x1b[90m", .{}),
            .BrightRed => try printer.print("\x1b[91m", .{}),
            .BrightGreen => try printer.print("\x1b[92m", .{}),
            .BrightYellow => try printer.print("\x1b[93m", .{}),
            .BrightBlue => try printer.print("\x1b[94m", .{}),
            .BrightMagenta => try printer.print("\x1b[95m", .{}),
            .BrightCyan => try printer.print("\x1b[96m", .{}),
            .BrightWhite => try printer.print("\x1b[97m", .{}),
            else => {},
        }
    }
};


const FilePrinterData = struct {
    alloc: std.mem.Allocator,
    file: std.fs.File,
    colorOutput: bool,
    bufferWriter: std.io.BufferedWriter(4096, std.fs.File.Writer),
};

const ArrayPrinterData = struct {
    array: std.ArrayList(u8),
    bufferWriter: std.io.BufferedWriter(4096, std.ArrayList(u8).Writer),
    alloc: std.mem.Allocator,
};

// An adapter for printing either to an ArrayList or to a File like stdout.
pub const Printer = union(enum) {
    file: *FilePrinterData,
    array: *ArrayPrinterData,
    _debug: bool,
    
    pub fn stdout(alloc: std.mem.Allocator) !Printer {
        var f = try alloc.create(FilePrinterData);
        f.alloc = alloc;
        f.file = std.io.getStdOut();
        f.colorOutput = f.file.getOrEnableAnsiEscapeSupport() and f.file.isTty();
        f.bufferWriter = std.io.bufferedWriter(f.file.writer());
        return .{.file = f};
    }

    pub fn memory(alloc: std.mem.Allocator) !Printer {
        var a = try alloc.create(ArrayPrinterData);
        a.alloc = alloc;
        a.array = std.ArrayList(u8).init(alloc);
        a.bufferWriter = std.io.bufferedWriter(a.array.writer());
        return .{.array = a};
    }

    pub fn debug() Printer {
        return .{ ._debug = true };
    }

    pub fn deinit(self: *Printer) void {
        switch(self.*) {
            .array => |arr| {
                arr.array.deinit();
                arr.alloc.destroy(self.array);
            },
            .file => |f| {
                f.alloc.destroy(self.file);
            },
            else => {}
        }
    }

    pub fn print(self: *const Printer, comptime format: []const u8, args: anytype) anyerror!void
    {
        switch(self.*) {
            .array => |_| try self.array.bufferWriter.writer().print(format, args),
            .file => |_| try self.file.bufferWriter.writer().print(format, args),
            ._debug => |_| std.debug.print(format, args),
        }
    }

    pub fn printNum(self: *const Printer, s: []const u8, num: usize) !void {
        var n = num;
        while (n > 0) {
            try self.print("{s}", .{s});
            n -= 1;
        }
    }

    pub fn flush(self: *const Printer) anyerror!void
    {
        switch(self.*) {
            .array => |_| try self.array.bufferWriter.flush(),
            .file => |_| try self.file.bufferWriter.flush(),
            ._debug => {},
        }
    }

    pub fn supportsColor(self: *const Printer) bool {
        switch(self.*) {
            .file => |f| return f.colorOutput,
            ._debug => |_| return std.io.getStdErr().supportsAnsiEscapeCodes(),
            else => { return false; },
        }
    }
    
    pub fn printWrapped(
            self: *Printer, 
            value: []const u8, 
            startLineLen: usize, 
            currIndentAmount: usize, 
            maxLineLength: usize
        ) !usize 
    {
        var start: usize = 0;
        var currLineLen = startLineLen;
        var prevWordLoc: usize = 0;

        var idx: usize = 0;
        while(idx < value.len) {
            if(value[idx] == ' ') {
                prevWordLoc = idx;
            }
            else if(value[idx] == '\n') {
                try self.print("{s}", .{value[start..idx]});
                try self.printNum(" ", currIndentAmount);
                currLineLen = currIndentAmount;
                start = idx + 1;
                idx += 1;
            }

            if((currLineLen + idx - start) >= maxLineLength) {
                // hyphenation here.
                if(start >= prevWordLoc) {
                    try self.print("{s}-\n", .{value[start..idx-1]});
                    try self.printNum(" ", currIndentAmount);
                    currLineLen = currIndentAmount;
                    start = idx - 1;
                    prevWordLoc = start;
                } 
                // word wrap break
                else {
                    try self.print("{s}\n", .{value[start..prevWordLoc]});
                    try self.printNum(" ", currIndentAmount);
                    currLineLen = currIndentAmount;
                    start = prevWordLoc + 1;
                }
            }

            idx += 1;
        }

        // TODO: add print rest of value in word wrap case.
        //if((currLineLen + left) >= maxLine)
        const left: usize = value.len - start;
        try self.print("{s}", .{value[start..start+left]});
        currLineLen += left;

        return currLineLen;
    }
};
