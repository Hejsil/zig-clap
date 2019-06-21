const std = @import("std");
const clap = @import("clap");

pub fn main() !void {
    const params = [_]clap.Param(void){clap.Param(void){
        .names = clap.Names{ .short = 'h', .long = "help" },
    }};

    var direct_allocator = std.heap.DirectAllocator.init();
    const allocator = &direct_allocator.allocator;
    defer direct_allocator.deinit();

    var iter = clap.args.OsIterator.init(allocator);
    defer iter.deinit();
    const exe = try iter.next();

    var args = try clap.ComptimeClap(void, params).parse(allocator, clap.args.OsIterator, &iter);
    defer args.deinit();

    _ = args.flag("--helps");
}
