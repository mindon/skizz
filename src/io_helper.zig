const std = @import("std");

/// Helper for stdout/stderr writing in Zig 0.16
/// Using file descriptors for cross-platform compatibility
pub fn writeStdout(bytes: []const u8) void {
    const stdout_file = std.fs.File{ .handle = if (@import("builtin").os.tag == .windows) std.os.windows.GetStdHandle(std.os.windows.STD_OUTPUT_HANDLE) catch return else 1 };
    stdout_file.writeAll(bytes) catch {};
}

pub fn writeStderr(bytes: []const u8) void {
    const stderr_file = std.fs.File{ .handle = if (@import("builtin").os.tag == .windows) std.os.windows.GetStdHandle(std.os.windows.STD_ERROR_HANDLE) catch return else 2 };
    stderr_file.writeAll(bytes) catch {};
}

/// Print formatted string to stdout
pub fn print(comptime fmt: []const u8, args: anytype) void {
    var buf: [4096]u8 = undefined;
    const result = std.fmt.bufPrint(&buf, fmt, args) catch {
        writeStdout(fmt);
        return;
    };
    writeStdout(result);
}

/// Print formatted string to stderr
pub fn printErr(comptime fmt: []const u8, args: anytype) void {
    var buf: [4096]u8 = undefined;
    const result = std.fmt.bufPrint(&buf, fmt, args) catch {
        writeStderr(fmt);
        return;
    };
    writeStderr(result);
}

/// Read a line from stdin - cross-platform implementation
/// Returns a slice of the provided buffer containing the line (without newline)
pub fn readLine(buf: []u8) ?[]const u8 {
    const stdin_file = std.fs.File{ .handle = if (@import("builtin").os.tag == .windows) std.os.windows.GetStdHandle(std.os.windows.STD_INPUT_HANDLE) catch return null else 0 };
    
    // Read byte by byte until newline
    var i: usize = 0;
    while (i < buf.len) {
        const bytes_read = stdin_file.read(buf[i..][0..1]) catch return if (i == 0) null else buf[0..i];
        
        if (bytes_read == 0) {
            // EOF
            if (i == 0) return null;
            return buf[0..i];
        }
        
        if (buf[i] == '\n') {
            // Remove carriage return if present (Windows compatibility)
            if (i > 0 and buf[i - 1] == '\r') {
                return buf[0..i - 1];
            }
            return buf[0..i];
        }
        
        i += 1;
    }
    
    // Buffer full
    return buf[0..i];
}

test "print" {
    print("Hello {s}!\n", .{"World"});
}
