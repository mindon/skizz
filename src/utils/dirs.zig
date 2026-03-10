const std = @import("std");
const builtin = @import("builtin");

/// Get the skills directory path
/// - projectLocal: if true, use current working directory; otherwise use home directory
/// - universal: if true, use .agent/skills; otherwise use .claude/skills
pub fn getSkillsDir(allocator: std.mem.Allocator, project_local: bool, universal: bool) ![]const u8 {
    const folder = if (universal) ".agent/skills" else ".claude/skills";
    const io = @import("../cli.zig").getIo();
    const base = if (project_local) try std.process.currentPathAlloc(io, allocator) else try getHomeDir(allocator);
    defer allocator.free(base);

    return try std.fs.path.join(allocator, &.{ base, folder });
}

/// Get all search directories in priority order:
/// 1. Project universal (.agent/skills)
/// 2. Global universal (~/.agent/skills)
/// 3. Project claude (.claude/skills)
/// 4. Global claude (~/.claude/skills)
pub fn getSearchDirs(allocator: std.mem.Allocator) ![][]const u8 {
    var dirs: std.ArrayList([]const u8) = .empty;
    errdefer {
        for (dirs.items) |dir| allocator.free(dir);
        dirs.deinit(allocator);
    }

    const io = @import("../cli.zig").getIo();
    const cwd = try std.process.currentPathAlloc(io, allocator);
    defer allocator.free(cwd);

    const home = try getHomeDir(allocator);
    defer allocator.free(home);

    // 1. Project universal (.agent/skills)
    try dirs.append(allocator, try std.fs.path.join(allocator, &.{ cwd, ".agent", "skills" }));
    // 2. Global universal (~/.agent/skills)
    try dirs.append(allocator, try std.fs.path.join(allocator, &.{ home, ".agent", "skills" }));
    // 3. Project claude (.claude/skills)
    try dirs.append(allocator, try std.fs.path.join(allocator, &.{ cwd, ".claude", "skills" }));
    // 4. Global claude (~/.claude/skills)
    try dirs.append(allocator, try std.fs.path.join(allocator, &.{ home, ".claude", "skills" }));

    return try dirs.toOwnedSlice(allocator);
}

/// Get the user's home directory
pub fn getHomeDir(allocator: std.mem.Allocator) ![]const u8 {
    if (builtin.os.tag == .windows) {
        if (std.c.getenv("USERPROFILE")) |home| {
            return try allocator.dupe(u8, std.mem.span(home));
        } else {
            if (std.c.getenv("HOMEDRIVE")) |drive| {
                if (std.c.getenv("HOMEPATH")) |path| {
                    return try std.mem.concat(allocator, u8, &.{ std.mem.span(drive), std.mem.span(path) });
                }
            }
        }
    } else {
        if (std.c.getenv("HOME")) |home| {
            return try allocator.dupe(u8, std.mem.span(home));
        }
    }
    return error.HomeDirNotFound;
}

/// Expand ~ to home directory in path
pub fn expandPath(allocator: std.mem.Allocator, path: []const u8) ![]const u8 {
    if (path.len > 0 and path[0] == '~') {
        const home = try getHomeDir(allocator);
        defer allocator.free(home);
        if (path.len == 1) {
            return try allocator.dupe(u8, home);
        }
        return try std.fs.path.join(allocator, &.{ home, path[2..] });
    }
    return try allocator.dupe(u8, path);
}

/// Check if path is a local path (starts with /, ./, ../, ~/)
pub fn isLocalPath(path: []const u8) bool {
    if (path.len == 0) return false;
    if (path[0] == '/') return true;
    if (path[0] == '~') return true;
    if (path.len >= 2 and std.mem.eql(u8, path[0..2], "./")) return true;
    if (path.len >= 3 and std.mem.eql(u8, path[0..3], "../")) return true;
    return false;
}

/// Check if source is a git URL
pub fn isGitUrl(source: []const u8) bool {
    if (std.mem.startsWith(u8, source, "git@")) return true;
    if (std.mem.startsWith(u8, source, "git://")) return true;
    if (std.mem.startsWith(u8, source, "http://")) return true;
    if (std.mem.startsWith(u8, source, "https://")) return true;
    if (std.mem.endsWith(u8, source, ".git")) return true;
    return false;
}

/// Create directory recursively if it doesn't exist
pub fn ensureDir(path: []const u8) !void {
    const io = @import("../cli.zig").getIo();
    std.Io.Dir.createDirAbsolute(io, path, .default_dir) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        error.FileNotFound => {
            // Parent doesn't exist, create it first
            if (std.fs.path.dirname(path)) |parent| {
                try ensureDir(parent);
                try std.Io.Dir.createDirAbsolute(io, path, .default_dir);
            } else {
                return err;
            }
        },
        else => return err,
    };
}

/// Check if a directory exists
pub fn dirExists(path: []const u8) bool {
    const io = @import("../cli.zig").getIo();
    var dir = std.Io.Dir.openDirAbsolute(io, path, .{}) catch return false;
    dir.close(io);
    return true;
}

/// Check if a file exists
pub fn fileExists(path: []const u8) bool {
    const io = @import("../cli.zig").getIo();
    const file = std.Io.Dir.openFileAbsolute(io, path, .{}) catch return false;
    file.close(io);
    return true;
}

test "isLocalPath" {
    try std.testing.expect(isLocalPath("/absolute/path"));
    try std.testing.expect(isLocalPath("./relative/path"));
    try std.testing.expect(isLocalPath("../parent/path"));
    try std.testing.expect(isLocalPath("~/home/path"));
    try std.testing.expect(!isLocalPath("owner/repo"));
    try std.testing.expect(!isLocalPath("https://github.com/owner/repo"));
}

test "isGitUrl" {
    try std.testing.expect(isGitUrl("git@github.com:owner/repo.git"));
    try std.testing.expect(isGitUrl("https://github.com/owner/repo.git"));
    try std.testing.expect(isGitUrl("https://github.com/owner/repo"));
    try std.testing.expect(!isGitUrl("owner/repo"));
    try std.testing.expect(!isGitUrl("./local/path"));
}
