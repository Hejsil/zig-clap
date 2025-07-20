pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const params = comptime clap.parseParamsComptime(
        \\-h, --help         Display this help and exit.
        \\-v, --version      Output version information and exit.
        \\    --value <str>  An option parameter, which takes a value.
        \\
    );

    var res = try clap.parse(clap.Help, &params, clap.parsers.default, .{
        .allocator = gpa.allocator(),
    });
    defer res.deinit();

    // `clap.usage` is a function that can print a simple help message. It can print any `Param`
    // where `Id` has a `value` method (`Param(Help)` is one such parameter).
    if (res.args.help != 0) {
        var buf: [1024]u8 = undefined;
        var stderr = std.fs.File.stderr().writer(&buf);
        clap.usage(&stderr.interface, clap.Help, &params) catch {};
        try stderr.interface.flush();
        return;
    }
}

const clap = @import("clap");
const std = @import("std");
