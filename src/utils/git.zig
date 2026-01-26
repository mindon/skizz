const std = @import("std");
const dirs = @import("dirs.zig");

/// Clone a git repository to a temporary directory
/// Returns the path to the cloned directory
pub fn cloneRepo(allocator: std.mem.Allocator, source: []const u8) ![]const u8 {
    // Create temp directory
    const tmp_dir = try getTempDir(allocator);
    errdefer allocator.free(tmp_dir);

    // Build git URL
    const git_url = try buildGitUrl(allocator, source);
    defer allocator.free(git_url);

    // Run git clone
    const result = try runGitCommand(allocator, &.{ "git", "clone", "--depth", "1", git_url, tmp_dir });
    defer {
        allocator.free(result.stdout);
        allocator.free(result.stderr);
    }

    if (result.term.exited != 0) {
        std.debug.print("Git clone failed: {s}\n", .{result.stderr});
        return error.GitCloneFailed;
    }

    return tmp_dir;
}

/// Build git URL from source (handles GitHub shorthand like owner/repo)
pub fn buildGitUrl(allocator: std.mem.Allocator, source: []const u8) ![]const u8 {
    // Already a full URL
    if (std.mem.startsWith(u8, source, "git@") or
        std.mem.startsWith(u8, source, "http://") or
        std.mem.startsWith(u8, source, "https://") or
        std.mem.startsWith(u8, source, "git://"))
    {
        return try allocator.dupe(u8, source);
    }

    // GitHub shorthand: owner/repo or owner/repo/path
    // Extract owner/repo part
    var parts = std.mem.splitScalar(u8, source, '/');
    const owner = parts.next() orelse return error.InvalidSource;
    const repo = parts.next() orelse return error.InvalidSource;

    return try std.fmt.allocPrint(allocator, "https://github.com/{s}/{s}.git", .{ owner, repo });
}

/// Extract subpath from source (e.g., owner/repo/path/to/skill -> path/to/skill)
pub fn extractSubpath(allocator: std.mem.Allocator, source: []const u8) !?[]const u8 {
    // Skip if it's a full URL
    if (std.mem.startsWith(u8, source, "git@") or
        std.mem.startsWith(u8, source, "http://") or
        std.mem.startsWith(u8, source, "https://") or
        std.mem.startsWith(u8, source, "git://"))
    {
        return null;
    }

    var parts = std.mem.splitScalar(u8, source, '/');
    _ = parts.next(); // owner
    _ = parts.next(); // repo

    const rest = parts.rest();
    if (rest.len == 0) return null;

    return try allocator.dupe(u8, rest);
}

/// Get a temporary directory path
fn getTempDir(allocator: std.mem.Allocator) ![]const u8 {
    // Use random numbers for unique temp directory
    const io = @import("../cli.zig").getIo();
    var random_bytes: [12]u8 = undefined;
    io.random(&random_bytes);

    const random1 = std.mem.readInt(u64, random_bytes[0..8], .little);
    const random2 = std.mem.readInt(u32, random_bytes[8..12], .little);

    const tmp_base = "/tmp";
    return try std.fmt.allocPrint(allocator, "{s}/skizz-{d}-{d}", .{ tmp_base, random1, random2 });
}

/// Run a git command and return the result
fn runGitCommand(allocator: std.mem.Allocator, argv: []const []const u8) !std.process.RunResult {
    const io = @import("../cli.zig").getIo();
    return try std.process.run(allocator, io, .{
        .argv = argv,
    });
}

/// Check if git is available
pub fn isGitAvailable(allocator: std.mem.Allocator) bool {
    const result = runGitCommand(allocator, &.{ "git", "--version" }) catch return false;
    defer {
        allocator.free(result.stdout);
        allocator.free(result.stderr);
    }
    return result.term.exited == 0;
}

/// Find all SKILL.md files in a directory (recursively)
pub fn findSkillFiles(allocator: std.mem.Allocator, base_path: []const u8) ![][]const u8 {
    var results: std.ArrayList([]const u8) = .empty;
    errdefer {
        for (results.items) |item| allocator.free(item);
        results.deinit(allocator);
    }

    try findSkillFilesRecursive(allocator, base_path, base_path, &results, 0);

    return try results.toOwnedSlice(allocator);
}

fn findSkillFilesRecursive(
    allocator: std.mem.Allocator,
    base_path: []const u8,
    current_path: []const u8,
    results: *std.ArrayList([]const u8),
    depth: usize,
) !void {
    // Limit recursion depth
    if (depth > 10) return;

    const io = @import("../cli.zig").getIo();
    var dir = std.Io.Dir.openDirAbsolute(io, current_path, .{}) catch return;
    defer dir.close(io);

    var iter = dir.iterate();
    while (try iter.next(io)) |entry| {
        // Skip hidden directories and common non-skill directories
        if (entry.name[0] == '.') continue;
        if (std.mem.eql(u8, entry.name, "node_modules")) continue;

        const entry_path = try std.fs.path.join(allocator, &.{ current_path, entry.name });
        defer allocator.free(entry_path);

        if (entry.kind == .directory) {
            // Check for SKILL.md in this directory
            const skill_path = try std.fs.path.join(allocator, &.{ entry_path, "SKILL.md" });
            defer allocator.free(skill_path);

            if (dirs.fileExists(skill_path)) {
                // Calculate relative path from base
                // Use a simple string operation instead of relative()
                const rel_path = if (std.mem.startsWith(u8, entry_path, base_path))
                    try allocator.dupe(u8, entry_path[base_path.len..])
                else
                    try allocator.dupe(u8, entry_path);
                try results.append(allocator, rel_path);
            } else {
                // Recurse into subdirectory
                try findSkillFilesRecursive(allocator, base_path, entry_path, results, depth + 1);
            }
        }
    }
}

test "buildGitUrl" {
    const allocator = std.testing.allocator;

    // Full URL should be returned as-is
    const full_url = try buildGitUrl(allocator, "https://github.com/owner/repo.git");
    defer allocator.free(full_url);
    try std.testing.expectEqualStrings("https://github.com/owner/repo.git", full_url);

    // GitHub shorthand should be expanded
    const shorthand = try buildGitUrl(allocator, "owner/repo");
    defer allocator.free(shorthand);
    try std.testing.expectEqualStrings("https://github.com/owner/repo.git", shorthand);
}

test "extractSubpath" {
    const allocator = std.testing.allocator;

    // No subpath
    const no_subpath = try extractSubpath(allocator, "owner/repo");
    try std.testing.expect(no_subpath == null);

    // With subpath
    const with_subpath = try extractSubpath(allocator, "owner/repo/path/to/skill");
    defer if (with_subpath) |p| allocator.free(p);
    try std.testing.expect(with_subpath != null);
    try std.testing.expectEqualStrings("path/to/skill", with_subpath.?);
}
