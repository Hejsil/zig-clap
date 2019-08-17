const std = @import("std");
const clap = @import("clap");

pub fn main() !void {
    const allocator = std.heap.direct_allocator;

    const params = [_]clap.Param(void){clap.Param(void){
        .names = clap.Names{ .short = 'h', .long = "help" },
    }};

    var iter = clap.args.OsIterator.init(allocator);
    defer iter.deinit();
    const exe = try iter.next();

    var args = try clap.ComptimeClap(void, params).parse(allocator, clap.args.OsIterator, &iter);
    defer args.deinit();

    _ = args.flag("--helps");
}
