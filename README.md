<!---
README.md is autogenerated. Please edit example/README.md.template instead.
-->
# zig-clap

A simple and easy to use command line argument parser library for Zig.

The master branch of zig-clap targets the master branch of Zig. For a
version of zig-clap that targets a specific Zig release, have a look
at the releases. Each release specifies the Zig version it compiles with
in the release notes.

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

Automatically generated API Reference for the project
can be found at https://Hejsil.github.io/zig-clap.
Note that Zig autodoc is in beta; the website may be broken or incomplete.

## Examples

### `clap.parse`

The simplest way to use this library is to just call the `clap.parse` function.

```zig
const clap = @import("clap");
const std = @import("std");

const debug = std.debug;
const io = std.io;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    // First we specify what parameters our program can take.
    // We can use `parseParamsComptime` to parse a string into an array of `Param(Help)`
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
        // Report useful error and exit
        diag.report(io.getStdErr().writer(), err) catch {};
        return err;
    };
    defer res.deinit();

    if (res.args.help != 0)
        debug.print("--help\n", .{});
    if (res.args.number) |n|
        debug.print("--number = {}\n", .{n});
    for (res.args.string) |s|
        debug.print("--string = {s}\n", .{s});
    for (res.positionals) |pos|
        debug.print("{s}\n", .{pos});
}

```

The result will contain an `args` field and a `positionals` field. `args` will have one field
for each none positional parameter of your program. The name of the field will be the longest
name of the parameter.

The fields in `args` are typed. The type is based on the name of the value the parameter takes.
Since `--number` takes a `usize` the field `res.args.number` has the type `usize`.

Note that this is only the case because `clap.parsers.default` has a field called `usize` which
contains a parser that returns `usize`. You can pass in something other than
`clap.parsers.default` if you want some other mapping.

```zig
const clap = @import("clap");
const std = @import("std");

const debug = std.debug;
const io = std.io;
const process = std.process;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    // First we specify what parameters our program can take.
    // We can use `parseParamsComptime` to parse a string into an array of `Param(Help)`
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
    }) catch |err| {
        diag.report(io.getStdErr().writer(), err) catch {};
        return err;
    };
    defer res.deinit();

    if (res.args.help != 0)
        debug.print("--help\n", .{});
    if (res.args.number) |n|
        debug.print("--number = {}\n", .{n});
    if (res.args.answer) |a|
        debug.print("--answer = {s}\n", .{@tagName(a)});
    for (res.args.string) |s|
        debug.print("--string = {s}\n", .{s});
    for (res.positionals) |pos|
        debug.print("{s}\n", .{pos});
}

```

### `streaming.Clap`

The `streaming.Clap` is the base of all the other parsers. It's a streaming parser that uses an
`args.Iterator` to provide it with arguments lazily.

```zig
const clap = @import("clap");
const std = @import("std");

const debug = std.debug;
const io = std.io;
const process = std.process;

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

    var iter = try process.ArgIterator.initWithAllocator(allocator);
    defer iter.deinit();

    // Skip exe argument
    _ = iter.next();

    // Initialize our diagnostics, which can be used for reporting useful errors.
    // This is optional. You can also leave the `diagnostic` field unset if you
    // don't care about the extra information `Diagnostic` provides.
    var diag = clap.Diagnostic{};
    var parser = clap.streaming.Clap(u8, process.ArgIterator){
        .params = &params,
        .iter = &iter,
        .diagnostic = &diag,
    };

    // Because we use a streaming parser, we have to consume each argument parsed individually.
    while (parser.next() catch |err| {
        // Report useful error and exit
        diag.report(io.getStdErr().writer(), err) catch {};
        return err;
    }) |arg| {
        // arg.param will point to the parameter which matched the argument.
        switch (arg.param.id) {
            'h' => debug.print("Help!\n", .{}),
            'n' => debug.print("--number = {s}\n", .{arg.value.?}),

            // arg.value == null, if arg.param.takes_value == .none.
            // Otherwise, arg.value is the value passed with the argument, such as "-a=10"
            // or "-a 10".
            'f' => debug.print("{s}\n", .{arg.value.?}),
            else => unreachable,
        }
    }
}

```

Currently, this parser is the only parser that allows an array of `Param` that
is generated at runtime.

### `help`

The `help` prints a simple list of all parameters the program can take. It expects the
`Id` to have a `description` method and an `value` method so that it can provide that
in the output. `HelpOptions` is passed to `help` to control how the help message is
printed.

```zig
const clap = @import("clap");
const std = @import("std");

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
    // where `Id` has a `describtion` and `value` method (`Param(Help)` is one such parameter).
    // The last argument contains options as to how `help` should print those parameters. Using
    // `.{}` means the default options.
    if (res.args.help != 0)
        return clap.help(std.io.getStdErr().writer(), clap.Help, &params, .{});
}

```

```
$ zig-out/bin/help --help
    -h, --help
            Display this help and exit.

    -v, --version
            Output version information and exit.
```

### `usage`

The `usage` prints a small abbreviated version of the help message. It expects the `Id`
to have a `value` method so it can provide that in the output.

```zig
const clap = @import("clap");
const std = @import("std");

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
    if (res.args.help != 0)
        return clap.usage(std.io.getStdErr().writer(), clap.Help, &params);
}

```

```
$ zig-out/bin/usage --help
[-hv] [--value <str>]
```

