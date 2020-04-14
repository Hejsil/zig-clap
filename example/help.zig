const std = @import("std");
const clap = @import("clap");

pub fn main() !void {
    const stderr = std.io.getStdErr().outStream();

    // clap.help is a function that can print a simple help message, given a
    // slice of Param(Help). There is also a helpEx, which can print a
    // help message for any Param, but it is more verbose to call.
    try clap.help(
        stderr,
        comptime &[_]clap.Param(clap.Help){
            clap.parseParam("-h, --help     Display this help and exit.         ") catch unreachable,
            clap.parseParam("-v, --version  Output version information and exit.") catch unreachable,
        },
    );
}
