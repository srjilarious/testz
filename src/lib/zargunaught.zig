const std = @import("std");

pub const utils = @import("./utils.zig");
pub const help = @import("./helptext.zig");
pub const print = @import("./printer.zig");

pub const ParserConfigError = error{
    LongOptionNameMissing,
    OptionBeginsWithNumber,
    DuplicateOption,
    CommandNameMissing,
    DuplicateCommandName,
    CommandGroupNameMissing,
    // minNumParams is larger than maxNumParams.  Since maxNumParams
    // defaults to 0, this usually means an option that wants parameters
    // forgot to set maxNumParams.
    MinParamsExceedMax,
    // A default value carries more parameters than maxNumParams allows,
    // which is the same forgotten-maxNumParams mistake as above.
    DefaultParamsExceedMax,
    // defaultPositionalArgs must be DefaultValue.param or .params; .set
    // has no meaning for positional arguments.
    InvalidDefaultPositionalArgs,
    // In a positionals list, an optional argument comes before a required
    // one, or a repeating argument isn't the last.
    InvalidPositionals,
};

/// Returned by optionNumVal when the option wasn't given or has no value.
pub const ValueError = error{NoParamGiven};

pub const ParseError = error{
    UnknownOption,
    TooFewOptionParams,
    // A value was attached with `--opt=value` or `-ovalue` to an option
    // whose maxNumParams is 0.
    OptionTakesNoParams,
    TooManyOptionOccurences,
    TooFewPositionalArguments,
    TooManyPositionalArguments,
    StackedOptionCantTakeParams,
};

// Used to provide a list of parameters to an option when it takes
// multiple parameters.
const DefaultParameters = struct { values: []const []const u8 };

// Used to provide a single of parameter to an option when it takes
// one parameter.
const DefaultParameter = struct { value: []const u8 };

// Used to set an option to default on when it has no parameters.
const DefaultOption = struct { on: bool = true };

pub const DefaultValue = union(enum) {
    _params: DefaultParameters,
    _param: DefaultParameter,
    _set: DefaultOption,

    pub fn params(vals: []const []const u8) DefaultValue {
        return DefaultValue{ ._params = .{ .values = vals } };
    }

    pub fn param(val: []const u8) DefaultValue {
        return DefaultValue{ ._param = .{ .value = val } };
    }

    pub fn set() DefaultValue {
        return DefaultValue{ ._set = .{ .on = true } };
    }

    /// The parameter values this default supplies (none for `set`).
    pub fn values(self: *const DefaultValue) []const []const u8 {
        return switch (self.*) {
            ._params => |p| p.values,
            ._param => |*p| (&p.value)[0..1],
            ._set => &.{},
        };
    }
};

pub const Option = struct {
    longName: []const u8,
    shortName: []const u8 = "",
    description: []const u8 = "",
    // By default, an option can only appear once
    maxOccurences: ?u8 = 1,
    minNumParams: ?u8 = null,
    // Options are plain flags unless they ask for parameters.  null means
    // no limit: the option takes every following argument up to the next
    // option, so it will also swallow positional arguments after it.
    maxNumParams: ?u8 = 0,
    default: ?DefaultValue = null,
    // What help text calls this option's values, as in `--out <file>`.
    valueName: []const u8 = "value",
};

/// A named positional argument, for help text and usage lines.
pub const Positional = struct {
    name: []const u8,
    description: []const u8 = "",
    // Optional arguments must come after the required ones.
    optional: bool = false,
    // Only the last argument may repeat, e.g. `[path...]`.
    repeat: bool = false,
};

fn validatePositionals(positionals: []const Positional) ParserConfigError!void {
    var seenOptional = false;
    for (positionals, 0..) |p, i| {
        if (p.optional) {
            seenOptional = true;
        } else if (seenOptional) {
            return ParserConfigError.InvalidPositionals;
        }

        if (p.repeat and i != positionals.len - 1) {
            return ParserConfigError.InvalidPositionals;
        }
    }
}

/// The positional argument count limits a positionals list implies: one
/// per required argument at least, and no maximum when the last repeats.
const PositionalLimits = struct { min: ?u8, max: ?u8 };

fn positionalLimits(positionals: []const Positional) PositionalLimits {
    var required: u8 = 0;
    for (positionals) |p| {
        if (!p.optional) required += 1;
    }

    const repeats = positionals.len > 0 and positionals[positionals.len - 1].repeat;
    return .{
        .min = required,
        .max = if (repeats) null else @intCast(positionals.len),
    };
}

pub const OptionResult = struct {
    name: []const u8,
    values: std.ArrayList([]const u8),
    // Wider than maxOccurences, since an option without a limit can be
    // given any number of times.
    numOccurences: usize,

    pub fn init(name: []const u8) OptionResult {
        return .{
            .name = name,
            .values = .empty,
            .numOccurences = 0,
        };
    }

    pub fn deinit(self: *OptionResult, alloc: std.mem.Allocator) void {
        self.values.deinit(alloc);
    }
};

const OptionFindResult = struct {
    opt: ?Option,
    // The remainder of the short option text after finding a matching short option name.
    remaining: []const u8,
};

pub const OptionList = struct {
    data: std.ArrayList(Option),
    alloc: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) OptionList {
        return OptionList{ .data = .empty, .alloc = allocator };
    }

    pub fn deinit(self: *OptionList) void {
        self.data.deinit(self.alloc);
    }

    pub fn addOptions(self: *OptionList, opts: []const Option) (ParserConfigError || std.mem.Allocator.Error)!void {
        for (opts) |o| {
            try self.addOption(o);
        }
    }

    pub fn addOption(self: *OptionList, opt: Option) (ParserConfigError || std.mem.Allocator.Error)!void {
        try validateOption(opt);

        for (self.data.items) |o| {
            if (sameNames(opt, o)) {
                return ParserConfigError.DuplicateOption;
            }
        }

        try self.data.append(self.alloc, opt);
    }

    pub fn findLongOption(self: *const OptionList, optName: []const u8) ?Option {
        for (self.data.items) |opt| {
            if (std.mem.eql(u8, opt.longName, optName)) {
                return opt;
            }
        }

        return null;
    }

    /// Finds the short option `optName` starts with, leaving the rest of it
    /// in `remaining` so stacked options can be read one at a time.  The
    /// longest matching name wins, so with options `v` and `vx`, `-vx` is
    /// `vx` no matter which was defined first.
    pub fn findShortOption(self: *const OptionList, optName: []const u8) OptionFindResult {
        var best: ?Option = null;
        for (self.data.items) |opt| {
            if (opt.shortName.len == 0) continue;
            if (!std.mem.startsWith(u8, optName, opt.shortName)) continue;

            if (best == null or opt.shortName.len > best.?.shortName.len) {
                best = opt;
            }
        }

        if (best) |opt| {
            return .{ .opt = opt, .remaining = optName[opt.shortName.len..] };
        }
        return .{ .opt = null, .remaining = optName };
    }

    /// True when `text` splits entirely into this list's short option names,
    /// e.g. "vvx" with options v and x.
    fn isAllShortOptions(self: *const OptionList, text: []const u8) bool {
        var rest = text;
        while (rest.len > 0) {
            const found = self.findShortOption(rest);
            if (found.opt == null) return false;
            rest = found.remaining;
        }
        return true;
    }
};

fn validateOption(opt: Option) ParserConfigError!void {
    if (opt.longName.len == 0) {
        return ParserConfigError.LongOptionNameMissing;
    }

    if (std.ascii.isDigit(opt.longName[0])) {
        return ParserConfigError.OptionBeginsWithNumber;
    }

    if (opt.shortName.len > 0 and std.ascii.isDigit(opt.shortName[0])) {
        return ParserConfigError.OptionBeginsWithNumber;
    }

    if (opt.maxNumParams) |max| {
        if ((opt.minNumParams orelse 0) > max) {
            return ParserConfigError.MinParamsExceedMax;
        }

        if (opt.default) |*default| {
            if (default.values().len > max) {
                return ParserConfigError.DefaultParamsExceedMax;
            }
        }
    }
}

fn sameNames(a: Option, b: Option) bool {
    if (std.mem.eql(u8, a.longName, b.longName)) return true;
    return a.shortName.len > 0 and std.mem.eql(u8, a.shortName, b.shortName);
}

pub const Command = struct {
    name: []const u8,
    description: ?[]const u8 = null,
    group: ?[]const u8 = null,
    options: OptionList,
    // The command's own positional arguments, for help text.
    positionals: []const Positional = &.{},
    // Positional argument limits that replace the parser-wide ones while
    // this command is in use.  Each one left null falls back to the
    // matching ArgParserOpts limit.  When unset, they're worked out from
    // `positionals` if the command has any.
    minNumPositionalArgs: ?u8 = null,
    maxNumPositionalArgs: ?u8 = null,
};

pub const CommandList = struct {
    data: std.ArrayList(Command),
    alloc: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) CommandList {
        return CommandList{ .data = .empty, .alloc = allocator };
    }

    pub fn deinit(self: *CommandList) void {
        for (0..self.data.items.len) |idx| {
            self.data.items[idx].options.deinit();
        }

        self.data.deinit(self.alloc);
    }

    pub fn addMany(self: *CommandList, cmds: []const Command) (ParserConfigError || std.mem.Allocator.Error)!void {
        for (cmds) |c| {
            try self.add(c);
        }
    }

    /// Adds `cmd`, taking ownership of its option list.
    pub fn add(self: *CommandList, cmd: Command) (ParserConfigError || std.mem.Allocator.Error)!void {
        if (cmd.name.len == 0) {
            return ParserConfigError.CommandNameMissing;
        }

        if (self.find(cmd.name) != null) {
            return ParserConfigError.DuplicateCommandName;
        }

        try self.data.append(self.alloc, cmd);
    }

    pub fn find(self: *const CommandList, cmdName: []const u8) ?*Command {
        for (self.data.items) |*cmd| {
            if (std.mem.eql(u8, cmd.name, cmdName)) {
                return cmd;
            }
        }

        return null;
    }
};

/// The configuration options for a command used when setting
/// up the ArgParser.
pub const CommandOpt = struct {
    name: []const u8,
    description: ?[]const u8 = null,
    group: ?[]const u8 = null,
    opts: ?[]const Option = null,
    positionals: []const Positional = &.{},
    minNumPositionalArgs: ?u8 = null,
    maxNumPositionalArgs: ?u8 = null,
};

/// The parameters for a named group of commands.  This is just
/// a convenience wrapper for specifying the same group name on
/// each command diretly.
pub const GroupOpt = struct {
    name: []const u8,
    commands: []const CommandOpt,
    description: ?[]const u8 = null,
};

/// The top level configuration parameters for an ArgParser.
pub const ArgParserOpts = struct {
    name: ?[]const u8 = null,
    banner: ?[]const u8 = null,
    description: ?[]const u8 = null,
    usage: ?[]const u8 = null,
    // The program's positional arguments, listed in help text and used for
    // its usage line.  When minNumPositionalArgs and maxNumPositionalArgs
    // are unset, they're worked out from this list.
    positionals: []const Positional = &.{},
    minNumPositionalArgs: ?u8 = null,
    maxNumPositionalArgs: ?u8 = null,
    // Used as the positional arguments when the user gives none.
    defaultPositionalArgs: ?DefaultValue = null,
    // Options may normally appear anywhere, before or after positional
    // arguments.  Set this for wrapper style programs (`prog run cmd -x`)
    // where everything from the first positional argument on belongs to
    // something else and must be passed through untouched.
    stopAtFirstPositional: bool = false,
    opts: ?[]const Option = null,
    commands: ?[]const CommandOpt = null,
    groups: ?[]const GroupOpt = null,
};

pub const GroupData = struct {
    description: ?[]const u8 = null,
};

/// A zargunaught argument parser, with global options and commands.
pub const ArgParser = struct {
    name: []const u8,
    parserOpts: ArgParserOpts,
    options: OptionList,

    groupData: std.StringHashMap(GroupData),

    // Contains all commands, even grouped ones.
    commands: CommandList,
    alloc: std.mem.Allocator,

    // Copies of the process arguments made by `parse`.  Results point into
    // them, so they live as long as the parser (on Windows the argument
    // iterator frees its own strings when it is done).
    argArena: std.heap.ArenaAllocator,

    /// The argument that caused the last ParseError, for error messages.
    /// null after a successful parse and for positional count errors,
    /// which no single argument causes.
    failedArg: ?[]const u8 = null,

    pub fn init(allocator: std.mem.Allocator, opts: ArgParserOpts) !ArgParser {
        var argsParser = ArgParser{
            .name = opts.name orelse "",
            .parserOpts = opts,
            .options = OptionList.init(allocator),
            .commands = CommandList.init(allocator),
            .groupData = std.StringHashMap(GroupData).init(allocator),
            .alloc = allocator,
            .argArena = std.heap.ArenaAllocator.init(allocator),
        };
        errdefer argsParser.deinit();

        if (opts.opts) |globalOpts| {
            try argsParser.options.addOptions(globalOpts);
        }

        if (opts.defaultPositionalArgs) |default| {
            if (default == ._set) return ParserConfigError.InvalidDefaultPositionalArgs;
        }

        try validatePositionals(opts.positionals);
        if (opts.positionals.len > 0) {
            const limits = positionalLimits(opts.positionals);
            if (opts.minNumPositionalArgs == null) argsParser.parserOpts.minNumPositionalArgs = limits.min;
            if (opts.maxNumPositionalArgs == null) argsParser.parserOpts.maxNumPositionalArgs = limits.max;
        }

        if (opts.commands) |cmds| {
            for (cmds) |cmd| {
                try argsParser.addCommand(cmd, cmd.group);
            }
        }

        if (opts.groups) |groups| {
            for (groups) |group| {
                if (group.name.len == 0) return ParserConfigError.CommandGroupNameMissing;

                try argsParser.groupData.put(group.name, .{ .description = group.description });

                for (group.commands) |cmd| {
                    try argsParser.addCommand(cmd, group.name);
                }
            }
        }

        return argsParser;
    }

    fn addCommand(self: *ArgParser, cmd: CommandOpt, group: ?[]const u8) !void {
        var cmdItem: Command = .{
            .name = cmd.name,
            .description = cmd.description,
            .group = group,
            .options = OptionList.init(self.alloc),
            .positionals = cmd.positionals,
            .minNumPositionalArgs = cmd.minNumPositionalArgs,
            .maxNumPositionalArgs = cmd.maxNumPositionalArgs,
        };
        errdefer cmdItem.options.deinit();

        try validatePositionals(cmd.positionals);
        if (cmd.positionals.len > 0) {
            const limits = positionalLimits(cmd.positionals);
            if (cmd.minNumPositionalArgs == null) cmdItem.minNumPositionalArgs = limits.min;
            if (cmd.maxNumPositionalArgs == null) cmdItem.maxNumPositionalArgs = limits.max;
        }

        if (cmd.opts) |cmdOpts| {
            try cmdItem.options.addOptions(cmdOpts);

            // Global options stay usable after the command name, so a
            // command option may not reuse one of their names.
            for (cmdOpts) |o| {
                for (self.options.data.items) |g| {
                    if (sameNames(o, g)) return ParserConfigError.DuplicateOption;
                }
            }
        }

        try self.commands.add(cmdItem);
    }

    pub fn deinit(self: *ArgParser) void {
        self.options.deinit();
        self.commands.deinit();
        self.groupData.deinit();
        self.argArena.deinit();
    }

    pub fn parse(self: *ArgParser, args: std.process.Args) !ArgParserResult {
        const arena = self.argArena.allocator();
        var arr: std.ArrayList([]const u8) = .empty;

        var iter = try args.iterateAllocator(self.alloc);
        defer iter.deinit();
        _ = iter.next(); // Skip the program name.
        while (iter.next()) |curr| {
            try arr.append(arena, try arena.dupe(u8, curr));
        }

        return self.parseArray(arr.items);
    }

    /// Parses the array of string slices.  The result points into `args`
    /// and into this parser, so it must not outlive either of them.
    pub fn parseArray(self: *ArgParser, args: []const []const u8) (ParseError || std.mem.Allocator.Error)!ArgParserResult {
        self.failedArg = null;

        var parseResult = ArgParserResult.init(self.alloc);
        errdefer parseResult.deinit();

        var state = ParseState{
            .parser = self,
            .result = &parseResult,
            .args = args,
            .availableOpts = OptionList.init(self.alloc),
        };
        defer state.deinit();

        try state.availableOpts.data.appendSlice(self.alloc, self.options.data.items);

        try state.run();
        try state.applyDefaults();
        try state.checkPositionalCounts();

        return parseResult;
    }
};

/// True for an argument that should be read as an option: a dash followed
/// by something other than a digit.  A lone `-` (usually meaning stdin) and
/// negative numbers stay positional; option names can't start with a digit,
/// so `-5` is never ambiguous.
fn looksLikeOption(arg: []const u8) bool {
    return arg.len >= 2 and arg[0] == '-' and !std.ascii.isDigit(arg[1]);
}

/// The working state of one parseArray call.
const ParseState = struct {
    parser: *ArgParser,
    result: *ArgParserResult,
    args: []const []const u8,
    idx: usize = 0,

    // Global options, plus the command's once its name has been seen.
    availableOpts: OptionList,

    // Options switched off with `--no-name`, so defaults don't bring them back.
    unsetOptions: std.ArrayList([]const u8) = .empty,

    fn deinit(self: *ParseState) void {
        self.availableOpts.deinit();
        self.unsetOptions.deinit(self.parser.alloc);
    }

    fn fail(self: *ParseState, err: ParseError, arg: []const u8) ParseError {
        self.parser.failedArg = arg;
        return err;
    }

    fn run(self: *ParseState) !void {
        var onlyPositional = false;

        while (self.idx < self.args.len) {
            const arg = self.args[self.idx];

            if (onlyPositional) {
                try self.addPositional(arg);
                continue;
            }

            if (std.mem.eql(u8, arg, "--")) {
                self.idx += 1;
                onlyPositional = true;
                continue;
            }

            if (looksLikeOption(arg)) {
                try self.parseOption();
                continue;
            }

            // A command name is only recognized before any positional
            // argument, so a later positional that happens to match one
            // stays positional.
            if (self.result.command == null and self.result.positionalArgs.items.len == 0) {
                if (self.parser.commands.find(arg)) |cmd| {
                    self.result.command = cmd;
                    try self.availableOpts.data.appendSlice(self.parser.alloc, cmd.options.data.items);
                    self.idx += 1;
                    continue;
                }
            }

            try self.addPositional(arg);
            if (self.parser.parserOpts.stopAtFirstPositional) onlyPositional = true;
        }
    }

    fn addPositional(self: *ParseState, arg: []const u8) !void {
        try self.result.positionalArgs.append(self.result.alloc, arg);
        self.idx += 1;
    }

    fn parseOption(self: *ParseState) !void {
        const arg = self.args[self.idx];
        self.idx += 1;

        if (std.mem.startsWith(u8, arg, "--")) {
            try self.parseLongOption(arg);
        } else {
            try self.parseShortOptions(arg);
        }
    }

    fn parseLongOption(self: *ParseState, arg: []const u8) !void {
        var name = arg[2..];
        var attached: ?[]const u8 = null;
        if (std.mem.indexOfScalar(u8, name, '=')) |eq| {
            attached = name[eq + 1 ..];
            name = name[0..eq];
        }

        // An exact match wins, so an option really named `no-something`
        // still works.
        if (self.availableOpts.findLongOption(name)) |opt| {
            try self.addOccurrence(opt, arg);
            try self.takeParams(opt, attached, arg);
            return;
        }

        if (attached == null and std.mem.startsWith(u8, name, "no-")) {
            if (self.availableOpts.findLongOption(name[3..])) |opt| {
                try self.unsetOption(opt.longName);
                return;
            }
        }

        return self.fail(ParseError.UnknownOption, arg);
    }

    /// Handles `-v`, stacked flags like `-vvx`, and an attached value like
    /// `-b1`.  Within one argument, each option name is matched in turn.
    /// When an option that takes parameters is followed by text that isn't
    /// all option names, that text is its value.  Only an option standing
    /// alone in its argument takes parameters from the following arguments.
    fn parseShortOptions(self: *ParseState, arg: []const u8) !void {
        var rest = arg[1..];
        var alone = true;

        while (rest.len > 0) {
            const found = self.availableOpts.findShortOption(rest);
            const opt = found.opt orelse return self.fail(ParseError.UnknownOption, arg);
            rest = found.remaining;

            try self.addOccurrence(opt, arg);

            if (rest.len == 0) {
                if (alone) {
                    try self.takeParams(opt, null, arg);
                } else if ((opt.minNumParams orelse 0) > 0) {
                    return self.fail(ParseError.StackedOptionCantTakeParams, arg);
                }
                return;
            }

            if (opt.maxNumParams != 0 and !self.availableOpts.isAllShortOptions(rest)) {
                try self.takeParams(opt, rest, arg);
                return;
            }

            if ((opt.minNumParams orelse 0) > 0) {
                return self.fail(ParseError.StackedOptionCantTakeParams, arg);
            }

            alone = false;
        }
    }

    fn addOccurrence(self: *ParseState, opt: Option, arg: []const u8) !void {
        // A later `--name` overrides an earlier `--no-name`.
        for (self.unsetOptions.items, 0..) |unset, i| {
            if (std.mem.eql(u8, unset, opt.longName)) {
                _ = self.unsetOptions.orderedRemove(i);
                break;
            }
        }

        const optResult = self.result.option(opt.longName) orelse blk: {
            try self.result.options.append(self.result.alloc, OptionResult.init(opt.longName));
            break :blk &self.result.options.items[self.result.options.items.len - 1];
        };

        optResult.numOccurences += 1;
        if (opt.maxOccurences) |max| {
            if (optResult.numOccurences > max) {
                return self.fail(ParseError.TooManyOptionOccurences, arg);
            }
        }
    }

    /// Collects this occurrence's parameters: the attached value if there
    /// is one, otherwise following arguments up to maxNumParams, stopping
    /// at the next option or `--`.
    fn takeParams(self: *ParseState, opt: Option, attached: ?[]const u8, arg: []const u8) !void {
        const optResult = self.result.option(opt.longName).?;
        var taken: usize = 0;

        if (attached) |value| {
            if (opt.maxNumParams == 0) {
                return self.fail(ParseError.OptionTakesNoParams, arg);
            }
            try optResult.values.append(self.result.alloc, value);
            taken = 1;
        } else {
            while (self.idx < self.args.len) : (self.idx += 1) {
                if (opt.maxNumParams) |max| {
                    if (taken >= max) break;
                }

                const value = self.args[self.idx];
                if (looksLikeOption(value)) break;

                try optResult.values.append(self.result.alloc, value);
                taken += 1;
            }
        }

        if (taken < (opt.minNumParams orelse 0)) {
            return self.fail(ParseError.TooFewOptionParams, arg);
        }
    }

    /// `--no-name`: drops anything set so far and keeps the default off.
    fn unsetOption(self: *ParseState, longName: []const u8) !void {
        for (self.result.options.items, 0..) |*o, i| {
            if (std.mem.eql(u8, o.name, longName)) {
                o.deinit(self.result.alloc);
                _ = self.result.options.orderedRemove(i);
                break;
            }
        }

        for (self.unsetOptions.items) |unset| {
            if (std.mem.eql(u8, unset, longName)) return;
        }
        try self.unsetOptions.append(self.parser.alloc, longName);
    }

    fn applyDefaults(self: *ParseState) !void {
        const result = self.result;

        defaultOptLoop: for (self.availableOpts.data.items) |opt| {
            const default = opt.default orelse continue;
            if (result.hasOption(opt.longName)) continue;

            for (self.unsetOptions.items) |unset| {
                if (std.mem.eql(u8, opt.longName, unset)) continue :defaultOptLoop;
            }

            // A default of not set adds nothing.
            if (default == ._set and !default._set.on) continue;

            var optResult = OptionResult.init(opt.longName);
            errdefer optResult.deinit(result.alloc);
            try optResult.values.appendSlice(result.alloc, default.values());
            try result.options.append(result.alloc, optResult);
        }

        if (result.positionalArgs.items.len == 0) {
            if (self.parser.parserOpts.defaultPositionalArgs) |*default| {
                try result.positionalArgs.appendSlice(result.alloc, default.values());
            }
        }
    }

    fn checkPositionalCounts(self: *ParseState) ParseError!void {
        const conf = &self.parser.parserOpts;
        var minPosArgs = conf.minNumPositionalArgs;
        var maxPosArgs = conf.maxNumPositionalArgs;
        if (self.result.command) |cmd| {
            minPosArgs = cmd.minNumPositionalArgs orelse minPosArgs;
            maxPosArgs = cmd.maxNumPositionalArgs orelse maxPosArgs;
        }

        const count = self.result.positionalArgs.items.len;
        if (minPosArgs) |min| {
            if (count < min) return ParseError.TooFewPositionalArguments;
        }
        if (maxPosArgs) |max| {
            if (count > max) return ParseError.TooManyPositionalArguments;
        }
    }
};

/// The result from parsing arguments.
pub const ArgParserResult = struct {
    alloc: std.mem.Allocator,
    options: std.ArrayList(OptionResult),
    command: ?*Command,
    positionalArgs: std.ArrayList([]const u8),

    pub fn init(allocator: std.mem.Allocator) ArgParserResult {
        return .{
            .alloc = allocator,
            .options = .empty,
            .command = null,
            .positionalArgs = .empty,
        };
    }

    pub fn deinit(self: *ArgParserResult) void {
        for (0..self.options.items.len) |idx| {
            self.options.items[idx].deinit(self.alloc);
        }
        self.options.deinit(self.alloc);
        self.positionalArgs.deinit(self.alloc);
    }

    pub fn hasOption(self: *const ArgParserResult, name: []const u8) bool {
        return self.option(name) != null;
    }

    pub fn option(self: *const ArgParserResult, optName: []const u8) ?*OptionResult {
        for (self.options.items) |*o| {
            if (std.mem.eql(u8, o.name, optName)) {
                return o;
            }
        }

        return null;
    }

    // Get the first value if it exists.
    pub fn optionVal(self: *const ArgParserResult, optName: []const u8) ?[]const u8 {
        if (self.option(optName)) |o| {
            if (o.values.items.len > 0) {
                return o.values.items[0];
            }
        }

        return null;
    }

    pub fn optionValOrDefault(self: *const ArgParserResult, optName: []const u8, default: []const u8) []const u8 {
        return self.optionVal(optName) orelse default;
    }

    fn parseType(comptime T: type, val: []const u8) !T {
        return switch (@typeInfo(T)) {
            .int => try std.fmt.parseInt(T, val, 0),
            .float => try std.fmt.parseFloat(T, val),
            else => @compileError("zargunaught can only parse integer and float values, not " ++ @typeName(T)),
        };
    }

    pub fn optionNumVal(self: *const ArgParserResult, comptime T: type, optName: []const u8) !T {
        const optVal = self.optionVal(optName) orelse return ValueError.NoParamGiven;
        return try parseType(T, optVal);
    }

    pub fn optionNumValOrDefault(self: *const ArgParserResult, comptime T: type, optName: []const u8, default: T) !T {
        const optVal = self.optionVal(optName) orelse return default;
        return try parseType(T, optVal);
    }

    pub fn numPositional(self: *const ArgParserResult) usize {
        return self.positionalArgs.items.len;
    }

    /// All positional arguments, in order.
    pub fn positionals(self: *const ArgParserResult) []const []const u8 {
        return self.positionalArgs.items;
    }

    pub fn positional(self: *const ArgParserResult, idx: usize) ?[]const u8 {
        if (idx >= self.numPositional()) return null;
        return self.positionalArgs.items[idx];
    }

    pub fn positionalVal(self: *const ArgParserResult, comptime T: type, idx: usize) !?T {
        const val = self.positional(idx) orelse return null;
        return try parseType(T, val);
    }
};
