const clap = @import("clap");
const std = @import("std");

const debug = std.debug;
const io = std.io;
const process = std.process;

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    // First we specify what parameters our program can take.
    // We can use `parseParam` to parse a string to a `Param(Help)`
    const params = comptime [_]clap.Param(clap.Help){
        clap.untyped.parseParam("-h, --help             Display this help and exit.") catch unreachable,
        clap.untyped.parseParam("-n, --number <NUM>     An option parameter, which takes a value.") catch unreachable,
        clap.untyped.parseParam("-s, --string <STR>...  An option parameter which can be specified multiple times.") catch unreachable,
        clap.untyped.parseParam("<POS>...") catch unreachable,
    };

    var iter = try process.ArgIterator.initWithAllocator(allocator);
    defer iter.deinit();

    // Skip exe argument
    _ = iter.next();

    // Initalize our diagnostics, which can be used for reporting useful errors.
    // This is optional. You can also pass `.{}` to `clap.parse` if you don't
    // care about the extra information `Diagnostics` provides.
    var diag = clap.Diagnostic{};
    var res = clap.untyped.parseEx(clap.Help, &params, &iter, .{
        .allocator = allocator,
        .diagnostic = &diag,
    }) catch |err| {
        // Report useful error and exit
        diag.report(io.getStdErr().writer(), err) catch {};
        return err;
    };
    defer res.deinit();

    if (res.args.help)
        debug.print("--help\n", .{});
    if (res.args.number) |n|
        debug.print("--number = {s}\n", .{n});
    for (res.args.string) |s|
        debug.print("--string = {s}\n", .{s});
    for (res.positionals) |pos|
        debug.print("{s}\n", .{pos});
}
