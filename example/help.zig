const clap = @import("clap");
const std = @import("std");

pub fn main() !void {
    // clap.help is a function that can print a simple help message, given a
    // slice of Param(Help). There is also a helpEx, which can print a
    // help message for any Param, but it is more verbose to call.
    try clap.help(
        std.io.getStdErr().writer(),
        comptime &.{
            clap.parseParam("-h, --help     Display this help and exit.         ") catch unreachable,
            clap.parseParam("-v, --version  Output version information and exit.") catch unreachable,
        },
    );
}
