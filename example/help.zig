const std = @import("std");
const clap = @import("clap");

pub fn main() !void {
    const stderr_file = try std.io.getStdErr();
    var stderr_out_stream = stderr_file.outStream();
    const stderr = &stderr_out_stream.stream;

    // clap.help is a function that can print a simple help message, given a
    // slice of Param([]const u8). There is also a helpEx, which can print a
    // help message for any Param, but it is more verbose to call.
    try clap.help(
        stderr,
        [_]clap.Param([]const u8){
            clap.Param([]const u8){
                .id = "Display this help and exit.",
                .names = clap.Names{ .short = 'h', .long = "help" },
            },
            clap.Param([]const u8){
                .id = "Output version information and exit.",
                .names = clap.Names{ .short = 'v', .long = "version" },
            },
        },
    );
}
