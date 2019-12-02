const std = @import("std");
const clap = @import("clap");

pub fn main() !void {
    // First we specify what parameters our program can take.
    // We can use `parseParam` to parse a string to a `Param(Help)`
    const params = comptime [_]clap.Param(clap.Help){
        clap.parseParam("-h, --help  Display this help and exit.") catch unreachable,
    };

    var args = try clap.parse(clap.Help, &params, std.heap.direct_allocator);
    defer args.deinit();

    _ = args.flag("--helps");
}
