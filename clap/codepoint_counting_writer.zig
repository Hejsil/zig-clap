/// A Writer that counts how many codepoints has been written to it.
/// Expects valid UTF-8 input, and does not validate the input.
pub const CodepointCountingWriter = struct {
    codepoints_written: u64 = 0,
    child_stream: *std.Io.Writer,
    interface: std.Io.Writer = .{
        .buffer = &.{},
        .vtable = &.{ .drain = drain },
    },

    const Self = @This();

    pub fn init(child_stream: *std.Io.Writer) Self {
        return .{
            .child_stream = child_stream,
        };
    }

    fn drain(w: *std.Io.Writer, data: []const []const u8, splat: usize) std.Io.Writer.Error!usize {
        const self: *Self = @alignCast(@fieldParentPtr("interface", w));
        var n_bytes_written: usize = 0;
        var i: usize = 0;

        while (i < data.len + splat - 1) : (i += 1) {
            const chunk = data[@min(i, data.len)];
            const bytes_and_codepoints = utf8CountCodepointsAllowTruncate(chunk) catch return std.Io.Writer.Error.WriteFailed;
            // Might not be the full input, so the leftover bytes are written on the next call.
            const bytes_to_write = chunk[0..bytes_and_codepoints.bytes];
            const amt = try self.child_stream.write(bytes_to_write);
            n_bytes_written += amt;
            const bytes_written = bytes_to_write[0..amt];
            self.codepoints_written += (utf8CountCodepointsAllowTruncate(bytes_written) catch return std.Io.Writer.Error.WriteFailed).codepoints;
        }
        return n_bytes_written;
    }
};

// Like `std.unicode.utf8CountCodepoints`, but on truncated input, it returns
// the number of codepoints up to that point.
// Does not validate UTF-8 beyond checking the start byte.
fn utf8CountCodepointsAllowTruncate(s: []const u8) !struct { bytes: usize, codepoints: usize } {
    const native_endian = @import("builtin").cpu.arch.endian();
    var len: usize = 0;

    const N = @sizeOf(usize);
    const MASK = 0x80 * (std.math.maxInt(usize) / 0xff);

    var i: usize = 0;
    while (i < s.len) {
        // Fast path for ASCII sequences
        while (i + N <= s.len) : (i += N) {
            const v = std.mem.readInt(usize, s[i..][0..N], native_endian);
            if (v & MASK != 0) break;
            len += N;
        }

        if (i < s.len) {
            const n = try std.unicode.utf8ByteSequenceLength(s[i]);
            // Truncated input; return the current counts.
            if (i + n > s.len) return .{ .bytes = i, .codepoints = len };

            i += n;
            len += 1;
        }
    }

    return .{ .bytes = i, .codepoints = len };
}

const testing = std.testing;

test CodepointCountingWriter {
    var discarding = std.Io.Writer.Discarding.init(&.{});
    var counting_stream = CodepointCountingWriter.init(&discarding.writer);

    const utf8_text = "blåhaj" ** 100;
    counting_stream.interface.writeAll(utf8_text) catch unreachable;
    const expected_count = try std.unicode.utf8CountCodepoints(utf8_text);
    try testing.expectEqual(expected_count, counting_stream.codepoints_written);
}

test "handles partial UTF-8 writes" {
    var buf: [100]u8 = undefined;
    var fbs = std.Io.Writer.fixed(&buf);
    var counting_stream = CodepointCountingWriter.init(&fbs);

    const utf8_text = "ååå";
    // `å` is represented as `\xC5\xA5`, write 1.5 `å`s.
    var wc = try counting_stream.interface.write(utf8_text[0..3]);
    // One should have been written fully.
    try testing.expectEqual("å".len, wc);
    try testing.expectEqual(1, counting_stream.codepoints_written);

    // Write the rest, continuing from the reported number of bytes written.
    wc = try counting_stream.interface.write(utf8_text[wc..]);
    try testing.expectEqual(4, wc);
    try testing.expectEqual(3, counting_stream.codepoints_written);

    const expected_count = try std.unicode.utf8CountCodepoints(utf8_text);
    try testing.expectEqual(expected_count, counting_stream.codepoints_written);

    try testing.expectEqualSlices(u8, utf8_text, fbs.buffered());
}

const std = @import("std");
