const std = @import("std");
const clap = @import("clap");

const debug = std.debug;

pub fn main() !void {
    const allocator = std.heap.direct_allocator;

    // First we specify what parameters our program can take.
    // We can use `parseParam` to parse a string to a `Param(Help)`
    const params = comptime [_]clap.Param(clap.Help){
        clap.parseParam("-h, --help          Display this help and exit.              ") catch unreachable,
        clap.parseParam("-n, --number <NUM>  An option parameter, which takes a value.") catch unreachable,
        clap.Param(clap.Help){
            .takes_value = true,
        },
    };

    // We then initialize an argument iterator. We will use the OsIterator as it nicely
    // wraps iterating over arguments the most efficient way on each os.
    var iter = try clap.args.OsIterator.init(allocator);
    defer iter.deinit();

    // Parse the arguments
    var args = try clap.ComptimeClap(clap.Help, &params).parse(allocator, clap.args.OsIterator, &iter);
    defer args.deinit();

    if (args.flag("--help"))
        debug.warn("--help\n", .{});
    if (args.option("--number")) |n|
        debug.warn("--number = {}\n", .{ n });
    for (args.positionals()) |pos|
        debug.warn("{}\n", .{ pos });
}
