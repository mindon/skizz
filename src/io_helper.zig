const std = @import("std");

/// Write bytes to stdout
pub fn writeStdout(bytes: []const u8) void {
    std.debug.print("{s}", .{bytes});
}

/// Print formatted string to stdout
pub fn print(comptime fmt: []const u8, args: anytype) void {
    std.debug.print(fmt, args);
}

/// Print formatted string to stderr
pub fn printErr(comptime fmt: []const u8, args: anytype) void {
    std.debug.print(fmt, args);
}

/// Read a line from stdin - simplified for Zig 0.16
pub fn readLine(buf: []u8) ?[]const u8 {
    const stdin = std.Io.File.stdin();
    var i: usize = 0;

    while (i < buf.len) {
        var byte: [1]u8 = undefined;
        // Use os-level read through File.handle
        const bytes_read = switch (@import("builtin").os.tag) {
            .windows => std.os.windows.ReadFile(stdin.handle, &byte, null) catch return if (i == 0) null else buf[0..i],
            else => std.c.read(stdin.handle, &byte, 1),
        };

        if (bytes_read == 0) {
            return if (i == 0) null else buf[0..i];
        }

        if (byte[0] == '\n') {
            if (i > 0 and buf[i - 1] == '\r') {
                return buf[0..i - 1];
            }
            return buf[0..i];
        }

        buf[i] = byte[0];
        i += 1;
    }

    return buf[0..i];
}

test "print" {
    print("Hello {s}!\n", .{"World"});
}
