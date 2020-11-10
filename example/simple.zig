const std = @import("std");
const clap = @import("clap");

const debug = std.debug;

pub fn main() !void {
    // First we specify what parameters our program can take.
    // We can use `parseParam` to parse a string to a `Param(Help)`
    const params = comptime [_]clap.Param(clap.Help){
        clap.parseParam("-h, --help             Display this help and exit.              ") catch unreachable,
        clap.parseParam("-n, --number <NUM>     An option parameter, which takes a value.") catch unreachable,
        clap.parseParam("-s, --string <STR>...  An option parameter which can be specified multiple times.") catch unreachable,
        clap.parseParam("<POS>...") catch unreachable,
    };

    // Initalize our diagnostics, which can be used for reporting useful errors.
    // This is optional. You can also just pass `null` to `parser.next` if you
    // don't care about the extra information `Diagnostics` provides.
    var diag: clap.Diagnostic = undefined;

    var args = clap.parse(clap.Help, &params, std.heap.page_allocator, &diag) catch |err| {
        // Report useful error and exit
        diag.report(std.io.getStdErr().outStream(), err) catch {};
        return err;
    };
    defer args.deinit();

    if (args.flag("--help"))
        debug.warn("--help\n", .{});
    if (args.option("--number")) |n|
        debug.warn("--number = {}\n", .{n});
    for (args.options("--string")) |s|
        debug.warn("--string = {}\n", .{s});
    for (args.positionals()) |pos|
        debug.warn("{}\n", .{pos});
}
