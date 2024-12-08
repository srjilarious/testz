const std = @import("std");

pub export fn add(a: i32, b: i32) i32 {
    return a + b;
}

pub fn possibleError(val: bool) !i32 {
    if (val) return 123;

    return error.BadStuff;
}
