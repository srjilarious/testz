// zig fmt: off
const std = @import("std");

const printMod = @import("./printer.zig");
const Printer = printMod.Printer;
const Style = printMod.Style;
const zargs = @import("./zargunaught.zig");
const ArgParser = zargs.ArgParser;
const Option = zargs.Option;
const Command = zargs.Command;

fn optionHelpNameLength(opt: *const Option) usize {
    // + 2 for the dashes
    var optLen = opt.longName.len + 2;
    if(opt.shortName.len > 0) {
        // 2 for the ', ' and 1 for the dash
        optLen += opt.shortName.len + 2 + 1;
    }

    return optLen;
}

pub fn findMaxOptComLength(argsConf: *const ArgParser) usize
{
    var currMax: usize = 0;

    // Look at global options
    for(argsConf.options.data.items) |opt| {
        currMax = @max(optionHelpNameLength(&opt), currMax);
    }

    // Check the commands too
    for(argsConf.commands.data.items) |com| {
        currMax = @max(com.name.len, currMax);

        // Check the command options as well
        for(com.options.data.items) |opt| {
            // Account for extra 2 indentation for command options.
            currMax = @max(optionHelpNameLength(&opt) + 2, currMax);
        }
    }

    return currMax;
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
    .commandName = .{ .fg = .BrightBlue, .bg = . Reset, .mod = .{ .bold = true } },
    .groupName = .{ .fg = .BrightGreen, .bg = . Reset, .mod = .{ .underline = true } },
    .groupDescription = .{ .fg = .White, .bg = . Reset, .mod = .{ .italic = true } },
    .optionDash = .{ .fg = .Cyan, .bg = . Reset, .mod = .{ .dim = true } },
    .optionSeparator = .{ .fg = .White, .bg = . Reset, .mod = .{ .dim = true } },
    .separator = .{ .fg = .White, .bg = . Reset, .mod = .{ .dim = true } },
    .description = .{ .fg = .Reset, .bg = . Reset, .mod = .{} },
};

pub const HelpFormatter = struct 
{
    currLineLen: usize = 0,
    currIndentLevel: usize = 0,
    args: *const ArgParser,
    printer: Printer,
    theme: HelpTheme,
    alloc: std.mem.Allocator,
    commandGroups: std.StringHashMap(*CommandGroup),

    // A buffer used while printing so we can do word wrapping
    // properly.
    //buffer: [2048]u8,

    pub fn init(args: *const ArgParser, printer: Printer, theme: HelpTheme, alloc: std.mem.Allocator) !HelpFormatter 
    {
        var groups = std.StringHashMap(*CommandGroup).init(alloc);
        for(0..args.commands.data.items.len) |idx| {
            const cmd: *Command = &args.commands.data.items[idx];
            var groupName: []const u8 = "";
            if(cmd.group != null) {
                groupName = cmd.group.?;
            }

            if(!groups.contains(groupName)) {
                var group = try alloc.create(CommandGroup);
                group.* = CommandGroup.init(alloc);

                try group.append(cmd);
                try groups.put(groupName, group);
            } else {
                var group = groups.get(groupName).?;
                try group.append(cmd);
            }
        }

        return .{
            .currLineLen = 0,
            .currIndentLevel = 0,
            .args = args,
            .printer = printer,
            .theme = theme,
            .alloc = alloc,
            .commandGroups = groups,
        };
    }

    pub fn deinit(self: *HelpFormatter) void {
        // TODO: free up each command group.
        
        self.commandGroups.deinit();
    }

    fn printCommandGroup(self: *HelpFormatter, groupName: []const u8, group: *const CommandGroup, maxOptComLen: usize) !void {
        try self.theme.groupName.set(self.printer);

        if(std.mem.eql(u8, groupName, "")) {
            try self.printer.print("Commands", .{});
        }
        else {
            try self.printer.print("{s}", .{groupName});
        }

        try Style.reset(self.printer);

        // Print the group description if one exists.

        if(self.args.groupData.contains(groupName)) {
            const groupData = self.args.groupData.getPtr(groupName).?;
            if(groupData.*.description != null) {
                try self.newLine();
                try self.theme.groupDescription.set(self.printer);
                try self.printer.print("  {s}", .{groupData.*.description.?});
                try self.newLine();
                try Style.reset(self.printer);
            }
        }

        // Iterate over the commands.
        for(group.items) |com| {

            try Style.reset(self.printer);
            try self.newLine();

            try self.theme.commandName.set(self.printer);
            try self.printer.print("  {s}", .{com.name});


            // Print out the command description if there is one.
            if(com.description != null) {
                try self.theme.separator.set(self.printer);
                // Account for command not having dashes.
                try self.printer.printNum(" ", maxOptComLen - com.name.len + 2);
                try self.printer.print(": ", .{});

               try self.theme.description.set(self.printer);
                try self.printer.print("{?s}", .{com.description});
            }

            if(com.options.data.items.len > 0) {
                try self.newLine();
            }

            // Check the command options as well
            for(com.options.data.items) |opt| {
                try Style.reset(self.printer);
                try self.printer.print("    ", .{});

                try self.theme.optionName.set(self.printer);
                const optLen = try self.optionHelpName(&opt);

                try self.theme.separator.set(self.printer);

                // Account for extra 2 indentation for command option.
                try self.printer.printNum(" ", maxOptComLen - optLen - 2);
                try self.printer.print(": ", .{});


                try self.theme.description.set(self.printer);
                // try self.printer.print("{s}", .{opt.description});
                _ = try self.printer.printWrapped(
                        opt.description,
                        maxOptComLen + 2 + 4,
                        maxOptComLen + 2 + 4,
                        80
                    );
                try self.newLine();
            }
        }

        try self.newLine();
    }

    pub fn printHelpText(self: *HelpFormatter) !void
    {
        const maxOptComLen = findMaxOptComLength(self.args);

        try self.newLine();
        try self.theme.banner.set(self.printer);
        if(self.args.parserOpts.banner != null) {
            try self.printer.print("{?s}", .{self.args.parserOpts.banner});
        }
        else {
            try self.printer.print("{s}", .{self.args.name});
        }

        if(self.args.parserOpts.description != null) {
            try self.theme.separator.set(self.printer);
            try self.printer.print(" - ", .{});

            try self.theme.progDescription.set(self.printer);
            try self.printer.print("{?s}", .{self.args.parserOpts.description});
            try self.newLine();
        }

        try self.newLine();

        if(self.args.parserOpts.usage != null) {
            try self.theme.usage.set(self.printer);
            try self.printer.print("{?s}", .{self.args.parserOpts.usage});
            
            try self.newLine();
            try self.newLine();
        }

        if(self.args.options.data.items.len > 0) {
            try self.theme.groupName.set(self.printer);
            try self.printer.print("Global Options", .{});
            try Style.reset(self.printer);
            try self.newLine();

            // Look at global options
            for(self.args.options.data.items) |opt| {
                try Style.reset(self.printer);
                try self.printer.print("  ", .{});

                try self.theme.optionName.set(self.printer);
                const optLen = try self.optionHelpName(&opt);

                try self.theme.separator.set(self.printer);
                try self.printer.printNum(" ", maxOptComLen - optLen);
                try self.printer.print(": ", .{});

                try self.theme.description.set(self.printer);
                try self.printer.print("{s}", .{opt.description});
                try self.newLine();
            }

            try self.newLine();
        }

        var groupIterator = self.commandGroups.keyIterator();
        while(true) {
            const groupNamePtr = groupIterator.next();
            if(groupNamePtr == null) break;

            const groupName = groupNamePtr.?.*;
            const group = self.commandGroups.get(groupName).?;
            try self.printCommandGroup(groupName, group, maxOptComLen);
            try self.newLine();
        }

        // var groupDataIterator = self.args.groupData.keyIterator();
        // while(true) {
        //     const groupNamePtr = groupDataIterator.next();
        //     if(groupNamePtr == null) break;
        //
        //     const groupData = self.args.groupData.getPtr(groupNamePtr.?.*).?;
        //     std.debug.print("Group {s} - {?s}\n", .{groupNamePtr.?.*, groupData.*.description});
        // }
    }

    // fn indent(level: usize) void
    // {
    //
    // }

    fn optionHelpName(self: *HelpFormatter, opt: *const Option) !usize
    {
        var amount: usize = 0;
        try self.theme.optionDash.set(self.printer);
        try self.optionDash(.Long);
        try self.theme.optionName.set(self.printer);
        try self.printer.print("{s}", .{opt.longName});
        amount += opt.longName.len + 1;

        if(opt.shortName.len > 0) {
            try self.theme.optionSeparator.set(self.printer);
            try self.printer.print(", ", .{});
        
            try self.theme.optionDash.set(self.printer);
            try self.optionDash(.Short);
            try self.theme.optionName.set(self.printer);
            try self.printer.print("{s}", .{opt.shortName});
            amount += opt.shortName.len + 3;
        }

        return amount;
    }

    // fn optionHelpNameLength(self: *HelpFormatter) usize
    // {
    //
    // }

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
        self.currLineLen = 0;
    }

    // fn optionHelpName(self: *HelpFormatter) void
    // {
    //
    // }


};
