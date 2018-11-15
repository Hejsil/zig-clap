const std = @import("std");
const clap = @import("clap");

const debug = std.debug;

pub fn main() !void {
    var direct_allocator = std.heap.DirectAllocator.init();
    const allocator = &direct_allocator.allocator;
    defer direct_allocator.deinit();

    // First we specify what parameters our program can take.
    const params = []clap.Param(u8){
        clap.Param(u8).flag('h', clap.Names.both("help")),
        clap.Param(u8).option('n', clap.Names.both("number")),
        clap.Param(u8).positional('f'),
    };

    // We then initialize an argument iterator. We will use the OsIterator as it nicely
    // wraps iterating over arguments the most efficient way on each os.
    var os_iter = clap.args.OsIterator.init(allocator);
    const iter = &os_iter.iter;
    defer os_iter.deinit();

    // Consume the exe arg.
    const exe = try iter.next();

    // Finally we initialize our streaming parser.
    var parser = clap.StreamingClap(u8, clap.args.OsIterator.Error).init(params, iter);

    // Because we use a streaming parser, we have to consume each argument parsed individually.
    while (try parser.next()) |arg| {
        // arg.param will point to the parameter which matched the argument.
        switch (arg.param.id) {
            'h' => debug.warn("Help!\n"),
            'n' => debug.warn("--number = {}\n", arg.value.?),

            // arg.value == null, if arg.param.takes_value == false.
            // Otherwise, arg.value is the value passed with the argument, such as "-a=10"
            // or "-a 10".
            'f' => debug.warn("{}\n", arg.value.?),
            else => unreachable,
        }
    }
}
