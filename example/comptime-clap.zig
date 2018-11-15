const std = @import("std");
const clap = @import("clap");

const debug = std.debug;

pub fn main() !void {
    const stdout_file = try std.io.getStdOut();
    var stdout_out_stream = stdout_file.outStream();
    const stdout = &stdout_out_stream.stream;

    var direct_allocator = std.heap.DirectAllocator.init();
    const allocator = &direct_allocator.allocator;
    defer direct_allocator.deinit();

    // First we specify what parameters our program can take.
    const params = comptime []clap.Param([]const u8){
        clap.Param([]const u8).flag(
            "Display this help and exit.",
            clap.Names.both("help"),
        ),
        clap.Param([]const u8).option(
            "An option parameter, which takes a value.",
            clap.Names.both("number"),
        ),
        clap.Param([]const u8).positional(""),
    };

    // We then initialize an argument iterator. We will use the OsIterator as it nicely
    // wraps iterating over arguments the most efficient way on each os.
    var os_iter = clap.args.OsIterator.init(allocator);
    const iter = &os_iter.iter;
    defer os_iter.deinit();

    // Consume the exe arg.
    const exe = try iter.next();

    // Finally we can parse the arguments
    var args = try clap.ComptimeClap([]const u8, params).parse(allocator, clap.args.OsIterator.Error, iter);
    defer args.deinit();

    // clap.help is a function that can print a simple help message, given a
    // slice of Param([]const u8). There is also a helpEx, which can print a
    // help message for any Param, but it is more verbose to call.
    if (args.flag("--help"))
        return try clap.help(stdout, params);
    if (args.option("--number")) |n|
        debug.warn("--number = {}\n", n);
    for (args.positionals()) |pos|
        debug.warn("{}\n", pos);
}
