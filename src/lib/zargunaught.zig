// zig fmt: off
const std = @import("std");
const ArgQueue = std.TailQueue([]const u8);

pub const utils = @import("./utils.zig");

pub const ParserConfigError = error{ 
    LongOptionNameMissing,
    OptionBeginsWithNumber,
    DuplicateOption,
    CommandNameMissing,
    DuplicateCommandName,
    CommandGroupNameMissing,
};

pub const ParseError = error{UnknownOption};

pub const Option = struct {
    longName: []const u8,
    shortName: []const u8,
    description: []const u8,
    maxNumParams: i8 = 0,
};


pub const OptionResult = struct {
    name: []const u8,
    values: std.ArrayList([]const u8),

    pub fn init(name: []const u8) OptionResult {
        // TODO: fix allocator.
        return .{ .name = name, .values = std.ArrayList([]const u8).init(std.heap.page_allocator) };
    }

    pub fn deinit(self: *OptionResult) void {
        self.values.deinit();
    }
};

pub const OptionList = struct {
    data: std.ArrayList(Option),

    pub fn init(allocator: std.mem.Allocator) OptionList {
        const options = std.ArrayList(Option).init(allocator);
        return OptionList{ .data = options };
    }

    pub fn deinit(self: OptionList) void {
        self.data.deinit();
    }

    pub fn addOptions(self: *OptionList, opts: []const Option) ParserConfigError!void {
        for (opts) |o| {
            try self.addOption(o);
        }
    }

    pub fn addOption(self: *OptionList, opt: Option) ParserConfigError!void {
        if (opt.longName.len == 0) {
            return ParserConfigError.LongOptionNameMissing;
        }

        if (std.ascii.isDigit(opt.longName[0])) {
            return ParserConfigError.OptionBeginsWithNumber;
        }

        if (opt.shortName.len > 0 and std.ascii.isDigit(opt.shortName[0])) {
            return ParserConfigError.OptionBeginsWithNumber;
        }

        for (self.data.items) |o| {
            if (std.mem.eql(u8, opt.longName, o.longName)) {
                return ParserConfigError.DuplicateOption;
            }

            if (opt.shortName.len > 0 and std.mem.eql(u8, opt.shortName, o.shortName)) {
                return ParserConfigError.DuplicateOption;
            }
        }

        self.data.append(opt) catch unreachable;
    }

    pub fn findLongOption(self: *const OptionList, optName: []const u8) ?Option {
        for (self.data.items) |opt| {
            if (std.mem.eql(u8, opt.longName, optName)) {
                return opt;
            }
        }

        return null;
    }

    pub fn findShortOption(self: *const OptionList, optName: []const u8) ?Option {
        for (self.data.items) |opt| {
            if (std.mem.eql(u8, opt.shortName, optName)) {
                return opt;
            }
        }

        return null;
    }
};

pub const Command = struct { 
    name: []const u8, 
    description: ?[]const u8,
    options: OptionList 
};

pub const CommandList = struct {
    data: std.ArrayList(Command),

    pub fn init(allocator: std.mem.Allocator) CommandList {
        const data  = std.ArrayList(Command).init(allocator);
        return CommandList{ .data = data };
    }

    pub fn deinit(self: CommandList) void {
        for(self.data.items) |cmd| {
            cmd.options.deinit();
        }

        self.data.deinit();
    }

    pub fn addMany(self: *CommandList, cmds: []const Command) ParserConfigError!void {
        for (cmds) |c| {
            try self.add(c);
        }
    }

    pub fn add(self: *CommandList, cmd: Command) ParserConfigError!void {
        if (cmd.name.len == 0) {
            return ParserConfigError.CommandNameMissing;
        }

        for (self.data.items) |c| {
            if (std.mem.eql(u8, cmd.name, c.name)) {
                return ParserConfigError.DuplicateOption;
            }
        }

        self.data.append(cmd) catch unreachable;
    }

    pub fn find(self: *CommandList, cmdName: []const u8) ?Command {
        for (self.data.items) |cmd| {
            if (std.mem.eql(u8, cmd.name, cmdName)) {
                return cmd;
            }
        }

        return null;
    }
};

pub const CommandOpt = struct {
    name: []const u8,
    description: ?[]const u8 = null,
    // group: ?[]const u8,
    opts: ?[]const Option = null,
};

pub const ArgParserOpts = struct {
    name: ?[]const u8 = null,
    banner: ?[]const u8 = null,
    description: ?[]const u8 = null,
    usage: ?[]const u8 = null,
    opts: ?[]const Option = null,
    commands: ?[] const CommandOpt = null,
};

pub const ArgParser = struct {
    name: []const u8,
    banner: ?[]const u8,
    description: ?[]const u8,
    usage: ?[]const u8,
    options: OptionList,
    commands: CommandList,
    alloc: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, opts: ArgParserOpts) !ArgParser {
        var argsParser = ArgParser{ 
            .name = "", 
            .banner = opts.banner, 
            .description = opts.description, 
            .usage = opts.usage, 
            .options = OptionList.init(allocator),
            .commands = CommandList.init(allocator),
            .alloc = allocator
        };

        if(opts.name != null) {
            argsParser.name = opts.name.?;
        }

        if(opts.opts != null) {
            try argsParser.options.addOptions(opts.opts.?);
        }

        if(opts.commands != null) {
            for(opts.commands.?) |cmd| {
                var cmdItem: Command = .{
                    .name=cmd.name,
                    .description=cmd.description,
                    .options=OptionList.init(allocator)
                };

                if(cmd.opts != null) {
                    try cmdItem.options.addOptions(cmd.opts.?);
                }

                try argsParser.commands.data.append(cmdItem);
            }
        }
        return argsParser;
    }

    pub fn deinit(self: ArgParser) void {
        self.options.deinit();
        self.commands.deinit();
    }

    pub fn description(self: *ArgParser, desc: []const u8) *ArgParser {
        self.description = desc;
        return self;
    }

    pub fn usage(self: *ArgParser, use: []const u8) *ArgParser {
        self.usage = use;
        return self;
    }

    pub fn withOptions(self: *ArgParser, opts: []const Option) ParserConfigError!*ArgParser {
        try self.options.addOptions(opts);
        return self;
    }

    fn parseOption(parseText: *ArgQueue, parseResult: *ArgParserResult, availableOpts: *const OptionList) ParseError!?OptionResult {
        if (parseText.len == 0) return null;

        const optFullName = parseText.first.?.data;

        if (std.mem.eql(u8, optFullName, "-") or
            std.mem.eql(u8, optFullName, "--"))
        {
            _ = parseText.popFirst();
            parseResult.currItemPos += 1;
            return null;
        }

        var optName: []const u8 = undefined;
        var opt: ?Option = null;

        if (optFullName[0] == '-' and optFullName[1] == '-') {
            optName = optFullName[2..];
            opt = availableOpts.findLongOption(optName);
        }
        else if (optFullName[0] == '-') {
            optName = optFullName[1..];
            opt = availableOpts.findShortOption(optName);
        }

        _ = parseText.popFirst();
        parseResult.currItemPos += 1;

        if (opt != null) {
            var optResult = OptionResult.init(opt.?.longName);

            var paramCounter: usize = 0;
            while (parseText.len > 0 and
                (opt.?.maxNumParams == -1 or
                paramCounter < opt.?.maxNumParams)) : (paramCounter += 1)
            {
                const currVal = parseText.first.?.data;
                if (currVal[0] == '-' and currVal.len > 1) {
                    if (!std.ascii.isDigit(currVal[1])) break;
                }

                optResult.values.append(currVal) catch return null;
                _ = parseText.popFirst();
                parseResult.currItemPos += 1;

                paramCounter += 1;

                // std.debug.print("    Option param: {s}\n", .{currVal});
            }

            return optResult;
        } else {
            return ParseError.UnknownOption;
        }

        return null;
    }

    fn isNextItemLikelyAnOption(queue: *const ArgQueue) bool {
        return queue.len > 0 and 
               queue.first != null and 
               queue.first.?.data.len > 0 and
               queue.first.?.data[0] == '-';
    }

    pub fn parse(self: *ArgParser) !ArgParserResult 
    {
        var arr = std.ArrayList([]const u8).init(self.alloc);
        defer arr.deinit();

        var args = try std.process.argsWithAllocator(self.alloc);
        _ = args.next(); // Skip the program name.
        defer args.deinit();
        while(true) {
            const curr = args.next();
            if(curr == null) break;

            const argSlice = utils.cStrToSlice(curr.?);
            try arr.append(argSlice);
        }
        
        return self.parseArray(arr.items);
    }

    // TODO: Add in returning state for case where we hit `-`
    pub fn parseArgsForOptions(parseResult: *ArgParserResult, availableOpts: *const OptionList, parseText: *ArgQueue) !void
    {
        while (isNextItemLikelyAnOption(parseText)) {
            // Check if we ran into a number
            const frontData = parseText.first.?.data;
            if (frontData.len > 1 and std.ascii.isDigit(frontData[1])) break;

            // TODO: change to catching and adding a better error.
            const optRes = try parseOption(parseText, parseResult, availableOpts);
            if(optRes == null) break;

            try parseResult.options.append(optRes.?);
        }
    }

    // Parses the array of string slices.
    pub fn parseArray(self: *ArgParser, args: [][]const u8) !ArgParserResult 
    {
        // for (self.options.options.items) |opt| {
        //     std.debug.print("Option: --{s}, -{s}\n", .{ opt.longName, opt.shortName });
        // }

        var parseText = ArgQueue{};
        for (args) |arg| {
            const new_node = self.alloc.create(ArgQueue.Node) catch unreachable;
            new_node.* = ArgQueue.Node{ .prev = undefined, .next = undefined, .data = arg };
            parseText.append(new_node);
        }

        var parseResult = ArgParserResult.init(self.alloc);
        // var lastOpt: ?OptionResult = null;
        if(parseText.len == 0) return parseResult;

        try parseArgsForOptions(&parseResult, &self.options, &parseText);

        if(parseText.len == 0) return parseResult;

        // Setup command list.
        const frontData = parseText.first.?.data;

        // Handle looking for commands after any initial global options.
        for(0..self.commands.data.items.len) |cmdIdx| {
            const cmd: *Command = &self.commands.data.items[cmdIdx];
            if(std.mem.eql(u8, cmd.name, frontData)) {
                parseResult.command = cmd;

                _ = parseText.popFirst();

                // Create a temporary option list to use to find combined global and command level options.
                var availableOpts = OptionList.init(self.alloc);
                defer availableOpts.deinit();

                try availableOpts.addOptions(self.options.data.items);
                try availableOpts.addOptions(cmd.options.data.items);

                try parseArgsForOptions(&parseResult, &availableOpts, &parseText);
            }
        }

        // The rest of the arguments are positional.
        while(parseText.len > 0) {
            const posData = parseText.first.?.data;
            try parseResult.positional.append(posData);
            _ = parseText.popFirst();
        }
        return parseResult;
    }
};

pub const ArgParserResult = struct {
    // optionsList: OptionList, // Subparser options
    currItemPos: usize,
    options: std.ArrayList(OptionResult),
    command: ?*Command,
    positional: std.ArrayList([]const u8),

    pub fn init(allocator: std.mem.Allocator) ArgParserResult {
        return .{ 
            .currItemPos = 0, 
            .options = std.ArrayList(OptionResult).init(allocator),
            .command = null,
            .positional = std.ArrayList([]const u8).init(allocator) };
    }

    pub fn deinit(self: *ArgParserResult) void {
        self.options.deinit();
        self.positional.deinit();
    }

    pub fn hasOption(self: *ArgParserResult, name: []const u8) bool {
        for(self.options.items) |o| {
            if(std.mem.eql(u8, o.name, name)) return true;
        }

        return false;
    }
};



