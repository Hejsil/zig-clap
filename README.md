# zig-clap

A simple and easy to use command line argument parser library for Zig.

## Installation

Developers tend to either use
* The latest tagged release of Zig
* The latest build of Zigs master branch

Depending on which developer you are, you need to run different `zig fetch` commands:

```sh
# Version of zig-clap that works with a tagged release of Zig
# Replace `<REPLACE ME>` with the version of zig-clap that you want to use
# See: https://github.com/Hejsil/zig-clap/releases
zig fetch --save https://github.com/Hejsil/zig-clap/archive/refs/tags/<REPLACE ME>.tar.gz

# Version of zig-clap that works with latest build of Zigs master branch
zig fetch --save git+https://github.com/Hejsil/zig-clap
```

Then add the following to `build.zig`:

```zig
const clap = b.dependency("clap", .{});
exe.root_module.addImport("clap", clap.module("clap"));
```

## Features

* Short arguments `-a`
  * Chaining `-abc` where `a` and `b` does not take values.
  * Multiple specifications are tallied (e.g. `-v -v`).
* Long arguments `--long`
* Supports both passing values using spacing and `=` (`-a 100`, `-a=100`)
  * Short args also support passing values with no spacing or `=` (`-a100`)
  * This all works with chaining (`-ba 100`, `-ba=100`, `-ba100`)
* Supports options that can be specified multiple times (`-e 1 -e 2 -e 3`)
* Print help message from parameter specification.
* Parse help message to parameter specification.

## API Reference

Automatically generated API Reference for the project can be found at
https://Hejsil.github.io/zig-clap. Note that Zig autodoc is in beta; the website
may be broken or incomplete.

## Examples

### `clap.parse`

The simplest way to use this library is to just call the `clap.parse` function.

```zig
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    // First we specify what parameters our program can take.
    // We can use `parseParamsComptime` to parse a string into an array of `Param(Help)`.
    const params = comptime clap.parseParamsComptime(
        \\-h, --help             Display this help and exit.
        \\-n, --number <usize>   An option parameter, which takes a value.
        \\-s, --string <str>...  An option parameter which can be specified multiple times.
        \\<str>...
        \\
    );

    // Initialize our diagnostics, which can be used for reporting useful errors.
    // This is optional. You can also pass `.{}` to `clap.parse` if you don't
    // care about the extra information `Diagnostics` provides.
    var diag = clap.Diagnostic{};
    var res = clap.parse(clap.Help, &params, clap.parsers.default, .{
        .diagnostic = &diag,
        .allocator = gpa.allocator(),
    }) catch |err| {
        // Report useful error and exit.
        var buf: [1024]u8 = undefined;
        var stderr = std.fs.File.stderr().writer(&buf);
        diag.report(&stderr.interface, err) catch {};
        try stderr.interface.flush();
        return err;
    };
    defer res.deinit();

    if (res.args.help != 0)
        std.debug.print("--help\n", .{});
    if (res.args.number) |n|
        std.debug.print("--number = {}\n", .{n});
    for (res.args.string) |s|
        std.debug.print("--string = {s}\n", .{s});
    for (res.positionals[0]) |pos|
        std.debug.print("{s}\n", .{pos});
}

const clap = @import("clap");
const std = @import("std");

```

The result will contain an `args` field and a `positionals` field. `args` will have one field for
each non-positional parameter of your program. The name of the field will be the longest name of the
parameter. `positionals` will be a tuple with one field for each positional parameter.

The fields in `args` and `postionals` are typed. The type is based on the name of the value the
parameter takes. Since `--number` takes a `usize` the field `res.args.number` has the type `usize`.

Note that this is only the case because `clap.parsers.default` has a field called `usize` which
contains a parser that returns `usize`. You can pass in something other than `clap.parsers.default`
if you want some other mapping.

```zig
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    // First we specify what parameters our program can take.
    // We can use `parseParamsComptime` to parse a string into an array of `Param(Help)`.
    const params = comptime clap.parseParamsComptime(
        \\-h, --help             Display this help and exit.
        \\-n, --number <INT>     An option parameter, which takes a value.
        \\-a, --answer <ANSWER>  An option parameter which takes an enum.
        \\-s, --string <STR>...  An option parameter which can be specified multiple times.
        \\<FILE>...
        \\
    );

    // Declare our own parsers which are used to map the argument strings to other
    // types.
    const YesNo = enum { yes, no };
    const parsers = comptime .{
        .STR = clap.parsers.string,
        .FILE = clap.parsers.string,
        .INT = clap.parsers.int(usize, 10),
        .ANSWER = clap.parsers.enumeration(YesNo),
    };

    var diag = clap.Diagnostic{};
    var res = clap.parse(clap.Help, &params, parsers, .{
        .diagnostic = &diag,
        .allocator = gpa.allocator(),
        // The assignment separator can be configured. `--number=1` and `--number:1` is now
        // allowed.
        .assignment_separators = "=:",
    }) catch |err| {
        var buf: [1024]u8 = undefined;
        var stderr = std.fs.File.stderr().writer(&buf);
        diag.report(&stderr.interface, err) catch {};
        try stderr.interface.flush();
        return err;
    };
    defer res.deinit();

    if (res.args.help != 0)
        std.debug.print("--help\n", .{});
    if (res.args.number) |n|
        std.debug.print("--number = {}\n", .{n});
    if (res.args.answer) |a|
        std.debug.print("--answer = {s}\n", .{@tagName(a)});
    for (res.args.string) |s|
        std.debug.print("--string = {s}\n", .{s});
    for (res.positionals[0]) |pos|
        std.debug.print("{s}\n", .{pos});
}

const clap = @import("clap");
const std = @import("std");

```

### Subcommands

There is an option for `clap.parse` and `clap.parseEx` called `terminating_positional`. It allows
for users of `clap` to implement subcommands in their cli application:

```zig
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
        var buf: [1024]u8 = undefined;
        var stderr = std.fs.File.stderr().writer(&buf);
        diag.report(&stderr.interface, err) catch {};
        try stderr.interface.flush();
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
        var buf: [1024]u8 = undefined;
        var stderr = std.fs.File.stderr().writer(&buf);
        diag.report(&stderr.interface, err) catch {};
        try stderr.interface.flush();
        return err; // propagate error
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

```

### `streaming.Clap`

The `streaming.Clap` is the base of all the other parsers. It's a streaming parser that uses an
`args.Iterator` to provide it with arguments lazily.

```zig
pub fn main() !void {
    const allocator = std.heap.page_allocator;

    // First we specify what parameters our program can take.
    const params = [_]clap.Param(u8){
        .{
            .id = 'h',
            .names = .{ .short = 'h', .long = "help" },
        },
        .{
            .id = 'n',
            .names = .{ .short = 'n', .long = "number" },
            .takes_value = .one,
        },
        .{ .id = 'f', .takes_value = .one },
    };

    var iter = try std.process.ArgIterator.initWithAllocator(allocator);
    defer iter.deinit();

    // Skip exe argument.
    _ = iter.next();

    // Initialize our diagnostics, which can be used for reporting useful errors.
    // This is optional. You can also leave the `diagnostic` field unset if you
    // don't care about the extra information `Diagnostic` provides.
    var diag = clap.Diagnostic{};
    var parser = clap.streaming.Clap(u8, std.process.ArgIterator){
        .params = &params,
        .iter = &iter,
        .diagnostic = &diag,
    };

    // Because we use a streaming parser, we have to consume each argument parsed individually.
    while (parser.next() catch |err| {
        // Report useful error and exit.
        var buf: [1024]u8 = undefined;
        var stderr = std.fs.File.stderr().writer(&buf);
        diag.report(&stderr.interface, err) catch {};
        try stderr.interface.flush();
        return err;
    }) |arg| {
        // arg.param will point to the parameter which matched the argument.
        switch (arg.param.id) {
            'h' => std.debug.print("Help!\n", .{}),
            'n' => std.debug.print("--number = {s}\n", .{arg.value.?}),

            // arg.value == null, if arg.param.takes_value == .none.
            // Otherwise, arg.value is the value passed with the argument, such as "-a=10"
            // or "-a 10".
            'f' => std.debug.print("{s}\n", .{arg.value.?}),
            else => unreachable,
        }
    }
}

const clap = @import("clap");
const std = @import("std");

```

```
$ zig-out/bin/streaming-clap --help --number=1 f=10
Help!
--number = 1
f=10
```

Currently, this parser is the only parser that allows an array of `Param` that is generated at runtime.

### `help`

`help` prints a simple list of all parameters the program can take. It expects the `Id` to have a
`description` method and an `value` method so that it can provide that in the output. `HelpOptions`
is passed to `help` to control how the help message is printed.

```zig
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const params = comptime clap.parseParamsComptime(
        \\-h, --help     Display this help and exit.
        \\-v, --version  Output version information and exit.
        \\
    );

    var res = try clap.parse(clap.Help, &params, clap.parsers.default, .{
        .allocator = gpa.allocator(),
    });
    defer res.deinit();

    // `clap.help` is a function that can print a simple help message. It can print any `Param`
    // where `Id` has a `description` and `value` method (`Param(Help)` is one such parameter).
    // The last argument contains options as to how `help` should print those parameters. Using
    // `.{}` means the default options.
    if (res.args.help != 0) {
        var buf: [1024]u8 = undefined;
        var stderr = std.fs.File.stderr().writer(&buf);
        clap.help(&stderr.interface, clap.Help, &params, .{}) catch {};
        try stderr.interface.flush();
        return;
    }
}

const clap = @import("clap");
const std = @import("std");

```

```
$ zig-out/bin/help --help
    -h, --help
            Display this help and exit.

    -v, --version
            Output version information and exit.
```

### `usage`

`usage` prints a small abbreviated version of the help message. It expects the `Id` to have a
`value` method so it can provide that in the output.

```zig
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

```

```
$ zig-out/bin/usage --help
[-hv] [--value <str>]
```

