const std = @import("std");
const printer = @import("./printer.zig");

const Color = printer.Color;
const TextStyle = printer.Color;
const Style = printer.Color;

pub const Styles = struct {
    value: Style,

    passTest: Style,
    skipTest: Style,
    errorTest: Style,
};
