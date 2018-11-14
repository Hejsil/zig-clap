const std = @import("std");
const clap = @import("clap");

const debug = std.debug;

pub fn main() !void {
    var direct_allocator = std.heap.DirectAllocator.init();
    const allocator = &direct_allocator.allocator;
    defer direct_allocator.deinit();

    // First we specify what parameters our program can take.
    const params = comptime []clap.Param(void){
        // Param.init takes 3 arguments.
        // * An "id", which can be any type specified by the argument to Param. The
        //   ComptimeClap expects clap.Param(void) only.
        // * A bool which determins wether the parameter takes a value.
        // * A "Names" struct, which determins what names the parameter will have on the
        //   commandline. Names.prefix inits a "Names" struct that has the "short" name
        //   set to the first letter, and the "long" name set to the full name.
        clap.Param(void).flag({}, clap.Names.prefix("help")),
        clap.Param(void).option({}, clap.Names.prefix("number")),

        // Names.positional returns a "Names" struct where neither the "short" or "long"
        // name is set.
        clap.Param(void).positional({}),
    };

    // We then initialize an argument iterator. We will use the OsIterator as it nicely
    // wraps iterating over arguments the most efficient way on each os.
    var os_iter = clap.args.OsIterator.init(allocator);
    const iter = &os_iter.iter;
    defer os_iter.deinit();

    // Consume the exe arg.
    const exe = try iter.next();

    // Finally we can parse the arguments
    var args = try clap.ComptimeClap(void, params).parse(allocator, clap.args.OsIterator.Error, iter);
    defer args.deinit();

    if (args.flag("--help"))
        debug.warn("Help!\n");
    if (args.option("--number")) |n|
        debug.warn("--number = {}\n", n);
    for (args.positionals()) |pos|
        debug.warn("{}\n", pos);
}
