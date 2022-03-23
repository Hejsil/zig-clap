const clap = @import("clap");
const std = @import("std");

pub fn main() !void {
    const params = comptime clap.parseParamsComptime(
        \\-h, --help     Display this help and exit.
        \\-v, --version  Output version information and exit.
        \\
    );

    var res = try clap.parse(clap.Help, &params, clap.parsers.default, .{});
    defer res.deinit();

    // clap.help is a function that can print a simple help message, given a
    // slice of Param(Help). There is also a helpEx, which can print a
    // help message for any Param, but it is more verbose to call.
    if (res.args.help)
        return clap.help(std.io.getStdErr().writer(), clap.Help, &params);
}
