// These are our subcommands.
const SubCommands = enum {
    help,
    math,
};

const main_parsers = .{
    .command = clap.parsers.enumeration(SubCommands),
};

// The parameters for `main`. Parameters for the subcommands are specified further down.
const main_params = clap.parseParamsComptime(
    \\-h, --help  Display this help and exit.
    \\<command>
    \\
);

// To pass around arguments returned by clap, `clap.Result` and `clap.ResultEx` can be used to
// get the return type of `clap.parse` and `clap.parseEx`.
const MainArgs = clap.ResultEx(clap.Help, &main_params, main_parsers);

pub fn main() !void {
    var gpa_state = std.heap.GeneralPurposeAllocator(.{}){};
    const gpa = gpa_state.allocator();
    defer _ = gpa_state.deinit();

    var iter = try std.process.ArgIterator.initWithAllocator(gpa);
    defer iter.deinit();

    _ = iter.next();

    var diag = clap.Diagnostic{};
    var res = clap.parseEx(clap.Help, &main_params, main_parsers, &iter, .{
        .diagnostic = &diag,
        .allocator = gpa,

        // Terminate the parsing of arguments after parsing the first positional (0 is passed
        // here because parsed positionals are, like slices and arrays, indexed starting at 0).
        //
        // This will terminate the parsing after parsing the subcommand enum and leave `iter`
        // not fully consumed. It can then be reused to parse the arguments for subcommands.
        .terminating_positional = 0,
    }) catch |err| {
        diag.report(std.io.getStdErr().writer(), err) catch {};
        return err;
    };
    defer res.deinit();

    if (res.args.help != 0)
        std.debug.print("--help\n", .{});

    const command = res.positionals[0] orelse return error.MissingCommand;
    switch (command) {
        .help => std.debug.print("--help\n", .{}),
        .math => try mathMain(gpa, &iter, res),
    }
}

fn mathMain(gpa: std.mem.Allocator, iter: *std.process.ArgIterator, main_args: MainArgs) !void {
    // The parent arguments are not used here, but there are cases where it might be useful, so
    // this example shows how to pass the arguments around.
    _ = main_args;

    // The parameters for the subcommand.
    const params = comptime clap.parseParamsComptime(
        \\-h, --help  Display this help and exit.
        \\-a, --add   Add the two numbers
        \\-s, --sub   Subtract the two numbers
        \\<isize>
        \\<isize>
        \\
    );

    // Here we pass the partially parsed argument iterator.
    var diag = clap.Diagnostic{};
    var res = clap.parseEx(clap.Help, &params, clap.parsers.default, iter, .{
        .diagnostic = &diag,
        .allocator = gpa,
    }) catch |err| {
        diag.report(std.io.getStdErr().writer(), err) catch {};
        return err;
    };
    defer res.deinit();

    const a = res.positionals[0] orelse return error.MissingArg1;
    const b = res.positionals[1] orelse return error.MissingArg1;
    if (res.args.help != 0)
        std.debug.print("--help\n", .{});
    if (res.args.add != 0)
        std.debug.print("added: {}\n", .{a + b});
    if (res.args.sub != 0)
        std.debug.print("subtracted: {}\n", .{a - b});
}

const clap = @import("clap");
const std = @import("std");
