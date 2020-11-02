const std = @import("std");
const clap = @import("clap");

const debug = std.debug;

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    // First we specify what parameters our program can take.
    const params = [_]clap.Param(u8){
        clap.Param(u8){
            .id = 'h',
            .names = clap.Names{ .short = 'h', .long = "help" },
        },
        clap.Param(u8){
            .id = 'n',
            .names = clap.Names{ .short = 'n', .long = "number" },
            .takes_value = .One,
        },
        clap.Param(u8){
            .id = 'f',
            .takes_value = .One,
        },
    };

    // We then initialize an argument iterator. We will use the OsIterator as it nicely
    // wraps iterating over arguments the most efficient way on each os.
    var iter = try clap.args.OsIterator.init(allocator);
    defer iter.deinit();

    // Initialize our streaming parser.
    var parser = clap.StreamingClap(u8, clap.args.OsIterator){
        .params = &params,
        .iter = &iter,
    };

    // Initalize our diagnostics, which can be used for reporting useful errors.
    // This is optional. You can also just pass `null` to `parser.next` if you
    // don't care about the extra information `Diagnostics` provides.
    var diag: clap.Diagnostic = undefined;

    // Because we use a streaming parser, we have to consume each argument parsed individually.
    while (parser.next(&diag) catch |err| {
        // Report useful error and exit
        diag.report(std.io.getStdErr().outStream(), err) catch {};
        return err;
    }) |arg| {
        // arg.param will point to the parameter which matched the argument.
        switch (arg.param.id) {
            'h' => debug.warn("Help!\n", .{}),
            'n' => debug.warn("--number = {}\n", .{arg.value.?}),

            // arg.value == null, if arg.param.takes_value == false.
            // Otherwise, arg.value is the value passed with the argument, such as "-a=10"
            // or "-a 10".
            'f' => debug.warn("{}\n", .{arg.value.?}),
            else => unreachable,
        }
    }
}
