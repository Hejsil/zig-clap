const std = @import("std");
const clap = @import("clap");

const debug = std.debug;

pub fn main() !void {
    const allocator = std.heap.direct_allocator;

    // First we specify what parameters our program can take.
    const params = [_]clap.Param([]const u8){
        clap.Param([]const u8){
            .id = "Display this help and exit.",
            .names = clap.Names{ .short = 'h', .long = "help" },
        },
        clap.Param([]const u8){
            .id = "An option parameter, which takes a value.",
            .names = clap.Names{ .short = 'n', .long = "number" },
            .takes_value = true,
        },
        clap.Param([]const u8){
            .id = "",
            .takes_value = true,
        },
    };

    // We then initialize an argument iterator. We will use the OsIterator as it nicely
    // wraps iterating over arguments the most efficient way on each os.
    var iter = clap.args.OsIterator.init(allocator);
    defer iter.deinit();

    // Consume the exe arg.
    const exe = try iter.next();

    // Finally we can parse the arguments
    var args = try clap.ComptimeClap([]const u8, params).parse(allocator, clap.args.OsIterator, &iter);
    defer args.deinit();

    if (args.flag("--help"))
        debug.warn("--help\n");
    if (args.option("--number")) |n|
        debug.warn("--number = {}\n", n);
    for (args.positionals()) |pos|
        debug.warn("{}\n", pos);
}
