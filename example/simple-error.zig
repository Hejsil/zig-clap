const std = @import("std");
const clap = @import("clap");

pub fn main() !void {
    const params = comptime [_]clap.Param(clap.Help){
        clap.parseParam("-h, --help  Display this help and exit.") catch unreachable,
    };

    var args = try clap.parse(clap.Help, &params, std.heap.direct_allocator, null);
    defer args.deinit();

    _ = args.flag("--helps");
}
