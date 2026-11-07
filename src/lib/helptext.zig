// zig fmt: off
const std = @import("std");

const printMod = @import("./printer.zig");
const Printer = printMod.Printer;
const Style = printMod.Style;
const zargs = @import("./zargunaught.zig");
const ArgParser = zargs.ArgParser;
const ArgParserResult = zargs.ArgParserResult;
const Option = zargs.Option;
const Command = zargs.Command;
const Positional = zargs.Positional;

// Lines are wrapped to this width.
const maxLineLength = 80;

// Command options sit this much further in than global options and
// commands in the full help.
const commandOptionIndent = 2;

// The names column grows to fit the longest name up to this width.  A
// longer name puts its description on the next line instead.
const maxNameColumn = 24;

fn takesSeveral(opt: *const Option) bool {
    return opt.maxNumParams == null or opt.maxNumParams.? > 1;
}

/// The printed width of the value placeholder after an option's names,
/// e.g. ` <value>` or ` [value...]`, or 0 for a flag.
fn placeholderLength(opt: *const Option) usize {
    if (opt.maxNumParams == 0) return 0;

    var len = 1 + 2 + opt.valueName.len;
    if (takesSeveral(opt)) len += 3;
    return len;
}

/// The printed width of an option's names and placeholder, e.g.
/// `--name, -n <value>`.
fn optionHelpNameLength(opt: *const Option) usize {
    // + 2 for the dashes
    var optLen = opt.longName.len + 2;
    if(opt.shortName.len > 0) {
        // 2 for the ', ' and 1 for the dash
        optLen += opt.shortName.len + 2 + 1;
    }

    return optLen + placeholderLength(opt);
}

fn capNameColumn(width: usize) usize {
    return @min(width, maxNameColumn);
}

/// The names column width for the full help: global options, the
/// program's positionals, commands, and command options (which sit
/// further in).
pub fn findMaxOptComLength(argsConf: *const ArgParser) usize
{
    var currMax: usize = 0;

    for(argsConf.options.data.items) |opt| {
        currMax = @max(optionHelpNameLength(&opt), currMax);
    }

    for(argsConf.parserOpts.positionals) |p| {
        currMax = @max(p.name.len, currMax);
    }

    for(argsConf.commands.data.items) |com| {
        currMax = @max(com.name.len, currMax);

        for(com.options.data.items) |opt| {
            currMax = @max(optionHelpNameLength(&opt) + commandOptionIndent, currMax);
        }
    }

    return capNameColumn(currMax);
}

/// The names column width for one command's help.
fn findCommandNameColumn(argsConf: *const ArgParser, cmd: *const Command) usize {
    var currMax: usize = 0;

    for(commandPositionals(argsConf, cmd)) |p| {
        currMax = @max(p.name.len, currMax);
    }

    for(cmd.options.data.items) |opt| {
        currMax = @max(optionHelpNameLength(&opt), currMax);
    }

    for(argsConf.options.data.items) |opt| {
        currMax = @max(optionHelpNameLength(&opt), currMax);
    }

    return capNameColumn(currMax);
}

/// A command's positionals, or the program's when the command lists none
/// (its positional limits fall back the same way).
fn commandPositionals(argsConf: *const ArgParser, cmd: *const Command) []const Positional {
    if (cmd.positionals.len > 0) return cmd.positionals;
    return argsConf.parserOpts.positionals;
}

const DashType = enum {
    Short,
    Long
};

pub const HelpTheme = struct {
    banner: Style,
    progDescription: Style,
    usage: Style,
    optionName: Style,
    optionValue: Style,
    positionalName: Style,
    commandName: Style,
    groupDescription: Style,
    groupName: Style,
    optionDash: Style,
    optionSeparator: Style,
    separator: Style,
    description: Style,
};

const CommandGroup = std.ArrayList(*Command);

pub const DefaultTheme: HelpTheme = .{
    .banner = .{ .fg = .BrightYellow, .bg = .Reset, .mod = .{ .bold = true } },
    .progDescription = .{ .fg = .BrightWhite, .bg = .Reset, .mod = .{ } },
    .usage = .{ .fg = .Reset , .bg = .Reset, .mod = .{ .italic = true } },
    .optionName = .{ .fg = .Cyan, .bg = . Reset, .mod = .{ .bold = true } },
    .optionValue = .{ .fg = .Cyan, .bg = . Reset, .mod = .{ .italic = true } },
    .positionalName = .{ .fg = .Magenta, .bg = . Reset, .mod = .{ .bold = true } },
    .commandName = .{ .fg = .BrightBlue, .bg = . Reset, .mod = .{ .bold = true } },
    .groupName = .{ .fg = .BrightGreen, .bg = . Reset, .mod = .{ .underline = true } },
    .groupDescription = .{ .fg = .White, .bg = . Reset, .mod = .{ .italic = true } },
    .optionDash = .{ .fg = .Cyan, .bg = . Reset, .mod = .{ .dim = true } },
    .optionSeparator = .{ .fg = .White, .bg = . Reset, .mod = .{ .dim = true } },
    .separator = .{ .fg = .White, .bg = . Reset, .mod = .{ .dim = true } },
    .description = .{ .fg = .Reset, .bg = . Reset, .mod = .{} },
};

/// Prints help text for an ArgParser to a Printer: Printer.stdout,
/// Printer.stderr, Printer.toFile or Printer.memory.
pub const HelpFormatter = struct
{
    args: *const ArgParser,
    printer: Printer,
    theme: HelpTheme,
    alloc: std.mem.Allocator,
    commandGroups: std.StringHashMap(*CommandGroup),

    // Group names in the order their first command was defined, so the
    // help text follows the configuration instead of hash map order.
    groupOrder: std.ArrayList([]const u8),

    pub fn init(args: *const ArgParser, printer: Printer, theme: HelpTheme, alloc: std.mem.Allocator) !HelpFormatter
    {
        var formatter: HelpFormatter = .{
            .args = args,
            .printer = printer,
            .theme = theme,
            .alloc = alloc,
            .commandGroups = std.StringHashMap(*CommandGroup).init(alloc),
            .groupOrder = .empty,
        };
        errdefer formatter.deinit();

        for(0..args.commands.data.items.len) |idx| {
            const cmd: *Command = &args.commands.data.items[idx];
            const groupName: []const u8 = cmd.group orelse "";

            if(formatter.commandGroups.get(groupName)) |group| {
                try group.append(alloc, cmd);
                continue;
            }

            const group = try alloc.create(CommandGroup);
            group.* = .empty;
            formatter.commandGroups.put(groupName, group) catch |err| {
                alloc.destroy(group);
                return err;
            };
            try group.append(alloc, cmd);
            try formatter.groupOrder.append(alloc, groupName);
        }

        return formatter;
    }

    pub fn deinit(self: *HelpFormatter) void {
        var it = self.commandGroups.valueIterator();
        while (it.next()) |group| {
            group.*.deinit(self.alloc);
            self.alloc.destroy(group.*);
        }

        self.commandGroups.deinit();
        self.groupOrder.deinit(self.alloc);
    }

    /// The help for whatever was parsed: the command's help when a command
    /// was given, so `prog cmd --help` describes `cmd`, otherwise the full
    /// help.
    pub fn printHelp(self: *HelpFormatter, result: *const ArgParserResult) !void {
        if (result.command) |cmd| {
            try self.printCommandHelp(cmd);
        } else {
            try self.printHelpText();
        }
    }

    /// The full help: every option, argument and command.
    pub fn printHelpText(self: *HelpFormatter) !void
    {
        const nameCol = findMaxOptComLength(self.args);
        const conf = &self.args.parserOpts;

        try self.newLine();
        try self.theme.banner.set(self.printer);
        try self.printer.print("{s}", .{conf.banner orelse self.args.name});

        if(conf.description) |description| {
            try self.theme.separator.set(self.printer);
            try self.printer.print(" - ", .{});

            try self.theme.progDescription.set(self.printer);
            try self.printer.print("{s}", .{description});
        }
        try Style.reset(self.printer);
        try self.newLine();
        try self.newLine();

        if(try self.printUsageLine(null)) {
            try self.newLine();
        }

        if(conf.usage) |usage| {
            try self.theme.usage.set(self.printer);
            _ = try self.printer.printWrapped(usage, 0, 0, maxLineLength);
            try Style.reset(self.printer);
            try self.newLine();
            try self.newLine();
        }

        try self.printPositionalSection(conf.positionals, nameCol);
        // "Global" only means something next to commands' own options.
        const optionsTitle = if (self.args.commands.data.items.len > 0) "Global Options" else "Options";
        try self.printOptionSection(optionsTitle, self.args.options.data.items, nameCol);

        for(self.groupOrder.items) |groupName| {
            const group = self.commandGroups.get(groupName).?;
            try self.printCommandGroup(groupName, group, nameCol);
        }

        try Style.reset(self.printer);
    }

    /// One command's help: its usage line, description, arguments and
    /// options, then the global options that also apply to it.
    pub fn printCommandHelp(self: *HelpFormatter, cmd: *const Command) !void {
        const nameCol = findCommandNameColumn(self.args, cmd);

        try self.newLine();
        _ = try self.printUsageLine(cmd);
        try self.newLine();

        if(cmd.description) |description| {
            try self.theme.progDescription.set(self.printer);
            _ = try self.printer.printWrapped(description, 0, 0, maxLineLength);
            try Style.reset(self.printer);
            try self.newLine();
            try self.newLine();
        }

        try self.printPositionalSection(commandPositionals(self.args, cmd), nameCol);
        try self.printOptionSection("Options", cmd.options.data.items, nameCol);
        try self.printOptionSection("Global Options", self.args.options.data.items, nameCol);

        try Style.reset(self.printer);
    }

    /// Prints `Usage: prog [options] [command] <args>`, or for a command
    /// `Usage: prog [options] cmd [options] <args>`.  Returns false, having
    /// printed nothing, when the parser has no name to show.
    fn printUsageLine(self: *HelpFormatter, cmd: ?*const Command) !bool {
        if (self.args.name.len == 0) return false;

        try self.theme.groupName.set(self.printer);
        try self.printer.print("Usage:", .{});
        try Style.reset(self.printer);
        try self.printer.print(" {s}", .{self.args.name});

        if (self.args.options.data.items.len > 0) {
            try self.printer.print(" [options]", .{});
        }

        var positionals = self.args.parserOpts.positionals;
        if (cmd) |c| {
            try self.theme.commandName.set(self.printer);
            try self.printer.print(" {s}", .{c.name});
            try Style.reset(self.printer);
            if (c.options.data.items.len > 0) {
                try self.printer.print(" [options]", .{});
            }
            positionals = commandPositionals(self.args, c);
        } else if (self.args.commands.data.items.len > 0) {
            try self.printer.print(" [command]", .{});
        }

        for (positionals) |p| {
            const open: []const u8 = if (p.optional) "[" else "<";
            const close: []const u8 = if (p.optional) "]" else ">";
            const more: []const u8 = if (p.repeat) "..." else "";
            try self.printer.print(" {s}", .{open});
            try self.theme.positionalName.set(self.printer);
            try self.printer.print("{s}", .{p.name});
            try Style.reset(self.printer);
            try self.printer.print("{s}{s}", .{ more, close });
        }

        try self.newLine();
        return true;
    }

    fn printSectionTitle(self: *HelpFormatter, title: []const u8) !void {
        try self.theme.groupName.set(self.printer);
        try self.printer.print("{s}", .{title});
        try Style.reset(self.printer);
        try self.newLine();
    }

    fn printPositionalSection(self: *HelpFormatter, positionals: []const Positional, nameCol: usize) !void {
        if (positionals.len == 0) return;

        try self.printSectionTitle("Arguments");
        for (positionals) |p| {
            try self.printer.print("  ", .{});
            try self.theme.positionalName.set(self.printer);
            try self.printer.print("{s}", .{p.name});
            try self.printDescription(p.description, 2 + p.name.len, nameCol);
            try Style.reset(self.printer);
            try self.newLine();
        }
        try self.newLine();
    }

    fn printOptionSection(self: *HelpFormatter, title: []const u8, opts: []const Option, nameCol: usize) !void {
        if (opts.len == 0) return;

        try self.printSectionTitle(title);
        for (opts) |*opt| {
            try self.printOptionRow(opt, 2, nameCol);
        }
        try self.newLine();
    }

    fn printOptionRow(self: *HelpFormatter, opt: *const Option, indent: usize, nameCol: usize) !void {
        try self.printer.printNum(" ", indent);
        const width = try self.optionHelpName(opt);

        const description = try self.describeOption(opt);
        defer self.alloc.free(description);
        try self.printDescription(description, indent + width, nameCol);

        try Style.reset(self.printer);
        try self.newLine();
    }

    /// The option's description with a note on how many values it takes
    /// (when the placeholder alone doesn't say) and its default.
    fn describeOption(self: *HelpFormatter, opt: *const Option) ![]u8 {
        var notes: std.ArrayList(u8) = .empty;
        defer notes.deinit(self.alloc);

        const min: usize = opt.minNumParams orelse 0;
        if (opt.maxNumParams) |max| {
            if (max > 1) {
                if (min == max) {
                    try notes.print(self.alloc, "{d} values", .{max});
                } else if (min == 0) {
                    try notes.print(self.alloc, "up to {d} values", .{max});
                } else {
                    try notes.print(self.alloc, "{d} to {d} values", .{ min, max });
                }
            }
        } else if (min > 1) {
            try notes.print(self.alloc, "at least {d} values", .{min});
        }

        if (opt.default) |*default| {
            if (notes.items.len > 0) try notes.appendSlice(self.alloc, ", ");
            switch (default.*) {
                ._set => |s| if (s.on) {
                    try notes.print(self.alloc, "on by default, --no-{s} turns it off", .{opt.longName});
                },
                else => {
                    try notes.appendSlice(self.alloc, "default: ");
                    for (default.values(), 0..) |value, i| {
                        if (i > 0) try notes.append(self.alloc, ' ');
                        try notes.appendSlice(self.alloc, value);
                    }
                },
            }
        }

        if (notes.items.len == 0) return try self.alloc.dupe(u8, opt.description);
        if (opt.description.len == 0) return try std.fmt.allocPrint(self.alloc, "({s})", .{notes.items});
        return try std.fmt.allocPrint(self.alloc, "{s} ({s})", .{ opt.description, notes.items });
    }

    /// Pads from `currCol` to the separator column, or moves to the next
    /// line when the name already reaches it, then prints the separator
    /// and the word-wrapped description.  Prints nothing for an empty
    /// description.
    fn printDescription(self: *HelpFormatter, description: []const u8, currCol: usize, nameCol: usize) !void {
        if (description.len == 0) return;

        const sepCol = 2 + nameCol + 1;
        try self.theme.separator.set(self.printer);
        if (currCol >= sepCol) {
            try self.newLine();
            try self.printer.printNum(" ", sepCol);
        } else {
            try self.printer.printNum(" ", sepCol - currCol);
        }
        try self.printer.print(": ", .{});

        try self.theme.description.set(self.printer);
        const descCol = sepCol + 2;
        _ = try self.printer.printWrapped(description, descCol, descCol, maxLineLength);
    }

    fn printCommandGroup(self: *HelpFormatter, groupName: []const u8, group: *const CommandGroup, nameCol: usize) !void {
        try self.printSectionTitle(if (groupName.len == 0) "Commands" else groupName);

        if(self.args.groupData.get(groupName)) |groupData| {
            if(groupData.description) |description| {
                try self.theme.groupDescription.set(self.printer);
                try self.printer.print("  ", .{});
                _ = try self.printer.printWrapped(description, 2, 2, maxLineLength);
                try Style.reset(self.printer);
                try self.newLine();
                try self.newLine();
            }
        }

        for(group.items, 0..) |com, i| {
            try self.theme.commandName.set(self.printer);
            try self.printer.print("  {s}", .{com.name});
            try self.printDescription(com.description orelse "", 2 + com.name.len, nameCol);
            try Style.reset(self.printer);
            try self.newLine();

            for(com.options.data.items) |*opt| {
                try self.printOptionRow(opt, 2 + commandOptionIndent, nameCol);
            }

            // A blank line sets a command's options apart from the next command.
            if(com.options.data.items.len > 0 and i + 1 < group.items.len) {
                try self.newLine();
            }
        }

        try self.newLine();
    }

    /// Prints `--name, -n <value>` and returns its width.
    fn optionHelpName(self: *HelpFormatter, opt: *const Option) !usize
    {
        try self.theme.optionDash.set(self.printer);
        try self.optionDash(.Long);
        try self.theme.optionName.set(self.printer);
        try self.printer.print("{s}", .{opt.longName});

        if(opt.shortName.len > 0) {
            try self.theme.optionSeparator.set(self.printer);
            try self.printer.print(", ", .{});

            try self.theme.optionDash.set(self.printer);
            try self.optionDash(.Short);
            try self.theme.optionName.set(self.printer);
            try self.printer.print("{s}", .{opt.shortName});
        }

        if(opt.maxNumParams != 0) {
            const required = (opt.minNumParams orelse 0) > 0;
            const open: []const u8 = if (required) "<" else "[";
            const close: []const u8 = if (required) ">" else "]";
            const more: []const u8 = if (takesSeveral(opt)) "..." else "";
            try self.theme.optionValue.set(self.printer);
            try self.printer.print(" {s}{s}{s}{s}", .{ open, opt.valueName, more, close });
        }

        return optionHelpNameLength(opt);
    }

    fn optionDash(self: *HelpFormatter, longDash: DashType) !void
    {
        switch(longDash) {
            .Long => try self.printer.print("--", .{}),
            .Short => try self.printer.print("-", .{})
        }
    }

    fn newLine(self: *HelpFormatter) !void
    {
        try self.printer.print("\n", .{});
    }
};
