/// A Writer that counts how many codepoints has been written to it.
/// Expects valid UTF-8 input, and does not validate the input.
pub fn CodepointCountingWriter(comptime WriterType: type) type {
    return struct {
        codepoints_written: u64,
        child_stream: WriterType,

        pub const Error = WriterType.Error || error{Utf8InvalidStartByte};
        pub const Writer = std.io.Writer(*Self, Error, write);

        const Self = @This();

        pub fn write(self: *Self, bytes: []const u8) Error!usize {
            const bytes_and_codepoints = try utf8CountCodepointsAllowTruncate(bytes);
            // Might not be the full input, so the leftover bytes are written on the next call.
            const bytes_to_write = bytes[0..bytes_and_codepoints.bytes];
            const amt = try self.child_stream.write(bytes_to_write);
            const bytes_written = bytes_to_write[0..amt];
            self.codepoints_written += (try utf8CountCodepointsAllowTruncate(bytes_written)).codepoints;
            return amt;
        }

        pub fn writer(self: *Self) Writer {
            return .{ .context = self };
        }
    };
}

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

pub fn codepointCountingWriter(child_stream: anytype) CodepointCountingWriter(@TypeOf(child_stream)) {
    return .{ .codepoints_written = 0, .child_stream = child_stream };
}

const testing = std.testing;

test CodepointCountingWriter {
    var counting_stream = codepointCountingWriter(std.io.null_writer);
    const stream = counting_stream.writer();

    const utf8_text = "blåhaj" ** 100;
    stream.writeAll(utf8_text) catch unreachable;
    const expected_count = try std.unicode.utf8CountCodepoints(utf8_text);
    try testing.expectEqual(expected_count, counting_stream.codepoints_written);
}

test "handles partial UTF-8 writes" {
    var buf: [100]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    var counting_stream = codepointCountingWriter(fbs.writer());
    const stream = counting_stream.writer();

    const utf8_text = "ååå";
    // `å` is represented as `\xC5\xA5`, write 1.5 `å`s.
    var wc = try stream.write(utf8_text[0..3]);
    // One should have been written fully.
    try testing.expectEqual("å".len, wc);
    try testing.expectEqual(1, counting_stream.codepoints_written);

    // Write the rest, continuing from the reported number of bytes written.
    wc = try stream.write(utf8_text[wc..]);
    try testing.expectEqual(4, wc);
    try testing.expectEqual(3, counting_stream.codepoints_written);

    const expected_count = try std.unicode.utf8CountCodepoints(utf8_text);
    try testing.expectEqual(expected_count, counting_stream.codepoints_written);

    try testing.expectEqualSlices(u8, utf8_text, fbs.getWritten());
}

const std = @import("std");
