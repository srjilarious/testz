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
    BrightWhite,
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
        // Keep escape codes out of piped or captured output.
        if (!printer.supportsColor()) return;
        try printer.print("\x1b[0m", .{});
    }

    pub fn set(self: *const Style, printer: Printer) !void {
        if (!printer.supportsColor()) return;

        if (self.fg == .Reset or self.bg == .Reset or self.mod.none()) {
            try reset(printer);
        }

        if (self.mod.dim) {
            try printer.print("\x1b[2m", .{});
        }
        if (self.mod.bold) {
            try printer.print("\x1b[1m", .{});
        }
        if (self.mod.italic) {
            try printer.print("\x1b[3m", .{});
        }
        if (self.mod.underline) {
            try printer.print("\x1b[4m", .{});
        }

        switch (self.bg) {
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

        switch (self.fg) {
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
    file: std.Io.File,
    buffer: []u8,
    colorOutput: bool,
    writer: std.Io.File.Writer,

    pub fn init(alloc: std.mem.Allocator, file: std.Io.File) !FilePrinterData {
        const io = std.Io.Threaded.global_single_threaded.io();
        const buffer = alloc.alloc(u8, 4096) catch return error.OutOfMemory;
        file.enableAnsiEscapeCodes(io) catch {};
        const colorOutput = (file.supportsAnsiEscapeCodes(io) catch false) and
            (file.isTty(io) catch false);
        return .{
            .alloc = alloc,
            .file = file,
            .buffer = buffer,
            .colorOutput = colorOutput,
            .writer = file.writer(io, buffer),
        };
    }

    pub fn deinit(self: *FilePrinterData) void {
        // So output isn't lost when the caller forgets to flush.
        self.writer.interface.flush() catch {};
        self.alloc.free(self.buffer);
    }
};

const ArrayPrinterData = struct {
    writer: std.Io.Writer.Allocating,
    alloc: std.mem.Allocator,
};

// An adapter for printing either to an ArrayList or to a File like stdout.
pub const Printer = union(enum) {
    file: *FilePrinterData,
    array: *ArrayPrinterData,
    _debug: bool,

    pub fn stdout(alloc: std.mem.Allocator) !Printer {
        return toFile(alloc, std.Io.File.stdout());
    }

    pub fn stderr(alloc: std.mem.Allocator) !Printer {
        return toFile(alloc, std.Io.File.stderr());
    }

    /// Prints to `file`, in color when it's a terminal that supports it.
    /// Call flush (or deinit) to write out what's buffered.
    pub fn toFile(alloc: std.mem.Allocator, file: std.Io.File) !Printer {
        const f = try alloc.create(FilePrinterData);
        f.* = FilePrinterData.init(alloc, file) catch {
            alloc.destroy(f);
            return error.OutOfMemory;
        };

        return .{ .file = f };
    }

    pub fn memory(alloc: std.mem.Allocator) !Printer {
        const a = try alloc.create(ArrayPrinterData);
        a.* = .{ .alloc = alloc, .writer = std.Io.Writer.Allocating.init(alloc) };
        return .{ .array = a };
    }

    pub fn debug() Printer {
        return .{ ._debug = true };
    }

    pub fn deinit(self: *Printer) void {
        switch (self.*) {
            .array => |arr| {
                arr.writer.deinit();
                arr.alloc.destroy(self.array);
            },
            .file => |f| {
                const alloc = f.alloc;
                f.deinit();
                alloc.destroy(self.file);
            },
            else => {},
        }
    }

    pub fn print(self: *const Printer, comptime format: []const u8, args: anytype) anyerror!void {
        switch (self.*) {
            .array => |a| try a.writer.writer.print(format, args),
            .file => |f| {
                try f.writer.interface.print(format, args);
            },
            ._debug => std.debug.print(format, args),
        }
    }

    pub fn printNum(self: *const Printer, s: []const u8, num: usize) !void {
        var n = num;
        while (n > 0) {
            try self.print("{s}", .{s});
            n -= 1;
        }
    }

    pub fn flush(self: *const Printer) anyerror!void {
        switch (self.*) {
            .array => {},
            .file => |f| try f.writer.interface.flush(),
            ._debug => {},
        }
    }

    pub fn supportsColor(self: *const Printer) bool {
        return switch (self.*) {
            .file => |f| f.colorOutput,
            ._debug => std.Io.File.stdout().supportsAnsiEscapeCodes(std.Io.Threaded.global_single_threaded.io()) catch false,
            else => {
                return false;
            },
        };
    }

    pub fn printWrapped(
        self: *Printer,
        value: []const u8,
        startLineLen: usize,
        currIndentAmount: usize,
        maxLineLength: usize,
    ) !usize {
        var col = startLineLen;

        // Newlines in `value` start a new indented line; the text between
        // them is wrapped word by word.
        var lines = std.mem.splitScalar(u8, value, '\n');
        var firstLine = true;
        while (lines.next()) |line| {
            if (!firstLine) {
                try self.wrapLine(currIndentAmount);
                col = currIndentAmount;
            }
            firstLine = false;

            var idx: usize = 0;
            while (idx < line.len) {
                // The spaces before a word are kept (so "end.  Next" keeps
                // its two spaces) unless the word moves to a new line.
                const gapStart = idx;
                while (idx < line.len and line[idx] == ' ') idx += 1;
                const gap = idx - gapStart;

                const wordStart = idx;
                while (idx < line.len and line[idx] != ' ') idx += 1;
                var word = line[wordStart..idx];

                // Trailing spaces are dropped.
                if (word.len == 0) break;

                if (col > currIndentAmount and col + gap + word.len > maxLineLength) {
                    try self.wrapLine(currIndentAmount);
                    col = currIndentAmount;
                } else {
                    try self.printNum(" ", gap);
                    col += gap;
                }

                // Hyphenate a word too long for a line of its own.  With
                // less than two columns of room there's nothing useful to
                // split into, so the word runs past the limit instead.
                while (col + word.len > maxLineLength) {
                    const room = maxLineLength -| col;
                    if (room < 2) break;

                    try self.print("{s}-", .{word[0 .. room - 1]});
                    try self.wrapLine(currIndentAmount);
                    col = currIndentAmount;
                    word = word[room - 1 ..];
                }

                try self.print("{s}", .{word});
                col += word.len;
            }
        }

        return col;
    }

    fn wrapLine(self: *Printer, indent: usize) !void {
        try self.print("\n", .{});
        try self.printNum(" ", indent);
    }
};
