const std = @import("std");
const clap = @import("clap");

pub fn main() !void {
    const stderr = std.io.getStdErr().outStream();

    // clap.usage is a function that can print a simple usage message, given a
    // slice of Param(Help). There is also a usageEx, which can print a
    // usage message for any Param, but it is more verbose to call.
    try clap.usage(
        stderr,
        comptime &[_]clap.Param(clap.Help){
            clap.parseParam("-h, --help       Display this help and exit.         ") catch unreachable,
            clap.parseParam("-v, --version    Output version information and exit.") catch unreachable,
            clap.parseParam("    --value <N>  Output version information and exit.") catch unreachable,
        },
    );
}
