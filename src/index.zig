const std = @import("std");

const debug = std.debug;

pub const @"comptime" = @import("comptime.zig");
pub const args = @import("args.zig");
pub const streaming = @import("streaming.zig");

test "clap" {
    _ = @"comptime";
    _ = args;
    _ = streaming;
}

pub const ComptimeClap = @"comptime".ComptimeClap;
pub const StreamingClap = streaming.StreamingClap;

/// The names a ::Param can have.
pub const Names = struct {
    /// '-' prefix
    short: ?u8,

    /// '--' prefix
    long: ?[]const u8,

    /// Initializes a short name
    pub fn short(s: u8) Names {
        return Names{
            .short = s,
            .long = null,
        };
    }

    /// Initializes a long name
    pub fn long(l: []const u8) Names {
        return Names{
            .short = null,
            .long = l,
        };
    }

    /// Initializes a name with a prefix.
    /// ::short is set to ::name[0], and ::long is set to ::name.
    /// This function asserts that ::name.len != 0
    pub fn prefix(name: []const u8) Names {
        debug.assert(name.len != 0);

        return Names{
            .short = name[0],
            .long = name,
        };
    }
};

/// Represents a parameter for the command line.
/// Parameters come in three kinds:
///   * Short ("-a"): Should be used for the most commonly used parameters in your program.
///     * They can take a value three different ways.
///       * "-a value"
///       * "-a=value"
///       * "-avalue"
///     * They chain if they don't take values: "-abc".
///       * The last given parameter can take a value in the same way that a single parameter can:
///         * "-abc value"
///         * "-abc=value"
///         * "-abcvalue"
///   * Long ("--long-param"): Should be used for less common parameters, or when no single character
///                            can describe the paramter.
///     * They can take a value two different ways.
///       * "--long-param value"
///       * "--long-param=value"
///   * Positional: Should be used as the primary parameter of the program, like a filename or
///                 an expression to parse.
///     * Positional parameters have both names.long and names.short == null.
///     * Positional parameters must take a value.
pub fn Param(comptime Id: type) type {
    return struct {
        id: Id,
        takes_value: bool,
        names: Names,

        pub fn flag(id: Id, names: Names) @This() {
            return init(id, false, names);
        }

        pub fn option(id: Id, names: Names) @This() {
            return init(id, true, names);
        }

        pub fn positional(id: Id) @This() {
            return init(id, true, Names{ .short = null, .long = null });
        }

        pub fn init(id: Id, takes_value: bool, names: Names) @This() {
            // Assert, that if the param have no name, then it has to take
            // a value.
            debug.assert(names.long != null or
                names.short != null or
                takes_value);

            return @This(){
                .id = id,
                .takes_value = takes_value,
                .names = names,
            };
        }
    };
}
