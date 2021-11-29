const clap = @import("clap");
const std = @import("std");

pub fn main() !void {
    const params = comptime [_]clap.Param(clap.Help){
        clap.parseParam("-h, --help     Display this help and exit.         ") catch unreachable,
        clap.parseParam("-v, --version  Output version information and exit.") catch unreachable,
    };

    var args = try clap.parse(clap.Help, &params, .{});
    defer args.deinit();

    // clap.help is a function that can print a simple help message, given a
    // slice of Param(Help). There is also a helpEx, which can print a
    // help message for any Param, but it is more verbose to call.
    if (args.flag("--help"))
        return clap.help(std.io.getStdErr().writer(), &params);
}
