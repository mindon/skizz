const std = @import("std");
const types = @import("../types.zig");
const dirs = @import("dirs.zig");
const yaml = @import("yaml.zig");

const SKILL_FILE = "SKILL.md";

/// Find all installed skills from all search directories
pub fn findAllSkills(allocator: std.mem.Allocator) ![]types.Skill {
    var skills: std.ArrayList(types.Skill) = .empty;
    errdefer {
        for (skills.items) |skill| {
            allocator.free(skill.name);
            allocator.free(skill.description);
            allocator.free(skill.path);
        }
        skills.deinit(allocator);
    }

    var seen = std.StringHashMap(void).init(allocator);
    defer {
        var it = seen.keyIterator();
        while (it.next()) |key| {
            allocator.free(key.*);
        }
        seen.deinit();
    }

    const search_dirs = try dirs.getSearchDirs(allocator);
    defer {
        for (search_dirs) |dir| allocator.free(dir);
        allocator.free(search_dirs);
    }

    const home = dirs.getHomeDir(allocator) catch "";
    defer if (home.len > 0) allocator.free(home);

    for (search_dirs) |search_dir| {
        var dir = std.fs.openDirAbsolute(search_dir, .{ .iterate = true }) catch continue;
        defer dir.close();

        var iter = dir.iterate();
        while (try iter.next()) |entry| {
            if (entry.kind != .directory and entry.kind != .sym_link) continue;

            // Check if already seen
            if (seen.contains(entry.name)) continue;

            // Check for SKILL.md
            const skill_path = try std.fs.path.join(allocator, &.{ search_dir, entry.name, SKILL_FILE });
            defer allocator.free(skill_path);

            if (!dirs.fileExists(skill_path)) continue;

            // Read skill content
            const content = readFileAlloc(allocator, skill_path) catch continue;
            defer allocator.free(content);

            // Extract description
            const description = try yaml.extractYamlField(allocator, content, "description");

            // Determine location
            const location: types.Skill.Location = if (home.len > 0 and std.mem.startsWith(u8, search_dir, home))
                .global
            else
                .project;

            // Add to seen set
            const name_copy = try allocator.dupe(u8, entry.name);
            try seen.put(name_copy, {});

            // Create skill entry
            const skill_path_copy = try std.fs.path.join(allocator, &.{ search_dir, entry.name, SKILL_FILE });
            const skill_name = try allocator.dupe(u8, entry.name);

            try skills.append(allocator, .{
                .name = skill_name,
                .description = description,
                .location = location,
                .path = skill_path_copy,
            });
        }
    }

    return try skills.toOwnedSlice(allocator);
}

/// Find a specific skill by name
pub fn findSkill(allocator: std.mem.Allocator, skill_name: []const u8) !?types.SkillLocation {
    const search_dirs = try dirs.getSearchDirs(allocator);
    defer {
        for (search_dirs) |dir| allocator.free(dir);
        allocator.free(search_dirs);
    }

    for (search_dirs) |search_dir| {
        const skill_path = try std.fs.path.join(allocator, &.{ search_dir, skill_name, SKILL_FILE });
        defer allocator.free(skill_path);

        if (dirs.fileExists(skill_path)) {
            const base_dir = try std.fs.path.join(allocator, &.{ search_dir, skill_name });
            const path = try std.fs.path.join(allocator, &.{ search_dir, skill_name, SKILL_FILE });
            const source = try allocator.dupe(u8, search_dir);

            return .{
                .path = path,
                .base_dir = base_dir,
                .source = source,
            };
        }
    }

    return null;
}

/// Free a SkillLocation
pub fn freeSkillLocation(allocator: std.mem.Allocator, loc: types.SkillLocation) void {
    allocator.free(loc.path);
    allocator.free(loc.base_dir);
    allocator.free(loc.source);
}

/// Free skills array
pub fn freeSkills(allocator: std.mem.Allocator, skills: []types.Skill) void {
    for (skills) |skill| {
        allocator.free(skill.name);
        allocator.free(skill.description);
        allocator.free(skill.path);
    }
    allocator.free(skills);
}

/// Read entire file into allocated buffer
pub fn readFileAlloc(allocator: std.mem.Allocator, path: []const u8) ![]const u8 {
    const file = try std.fs.openFileAbsolute(path, .{});
    defer file.close();

    const stat = try file.stat();
    const size = stat.size;

    if (size > 10 * 1024 * 1024) { // 10MB limit
        return error.FileTooLarge;
    }

    const buffer = try allocator.alloc(u8, size);
    errdefer allocator.free(buffer);

    const bytes_read = try file.preadAll(buffer, 0);
    if (bytes_read != size) {
        return error.UnexpectedEndOfFile;
    }

    return buffer;
}

/// Write content to file
pub fn writeFile(path: []const u8, content: []const u8) !void {
    const file = try std.fs.createFileAbsolute(path, .{});
    defer file.close();
    try file.writeAll(content);
}

/// Copy directory recursively
pub fn copyDir(allocator: std.mem.Allocator, src_path: []const u8, dst_path: []const u8) !void {
    // Create destination directory
    try dirs.ensureDir(dst_path);

    var src_dir = try std.fs.openDirAbsolute(src_path, .{ .iterate = true });
    defer src_dir.close();

    var iter = src_dir.iterate();
    while (try iter.next()) |entry| {
        const src_entry = try std.fs.path.join(allocator, &.{ src_path, entry.name });
        defer allocator.free(src_entry);

        const dst_entry = try std.fs.path.join(allocator, &.{ dst_path, entry.name });
        defer allocator.free(dst_entry);

        switch (entry.kind) {
            .directory => {
                try copyDir(allocator, src_entry, dst_entry);
            },
            .file => {
                const content = try readFileAlloc(allocator, src_entry);
                defer allocator.free(content);
                try writeFile(dst_entry, content);
            },
            .sym_link => {
                // Read symlink target and recreate
                var target_buf: [std.fs.max_path_bytes]u8 = undefined;
                const target = try src_dir.readLink(entry.name, &target_buf);
                try std.fs.symLinkAbsolute(target, dst_entry, .{});
            },
            else => {},
        }
    }
}

/// Remove directory recursively
pub fn removeDir(path: []const u8) !void {
    std.fs.deleteTreeAbsolute(path) catch |err| switch (err) {
        error.FileNotFound => {},
        else => return err,
    };
}

/// Get directory size in bytes
pub fn getDirSize(allocator: std.mem.Allocator, path: []const u8) !u64 {
    var total: u64 = 0;

    var dir = std.fs.openDirAbsolute(path, .{ .iterate = true }) catch return 0;
    defer dir.close();

    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        const entry_path = try std.fs.path.join(allocator, &.{ path, entry.name });
        defer allocator.free(entry_path);

        switch (entry.kind) {
            .directory => {
                total += try getDirSize(allocator, entry_path);
            },
            .file => {
                const file = std.fs.openFileAbsolute(entry_path, .{}) catch continue;
                defer file.close();
                const stat = try file.stat();
                total += stat.size;
            },
            else => {},
        }
    }

    return total;
}

/// Format bytes to human readable string
pub fn formatBytes(allocator: std.mem.Allocator, bytes: u64) ![]const u8 {
    const units = [_][]const u8{ "B", "KB", "MB", "GB" };
    var size: f64 = @floatFromInt(bytes);
    var unit_idx: usize = 0;

    while (size >= 1024 and unit_idx < units.len - 1) {
        size /= 1024;
        unit_idx += 1;
    }

    if (unit_idx == 0) {
        return try std.fmt.allocPrint(allocator, "{d} {s}", .{ bytes, units[0] });
    } else {
        return try std.fmt.allocPrint(allocator, "{d:.1} {s}", .{ size, units[unit_idx] });
    }
}

test "findSkill returns null for non-existent skill" {
    const allocator = std.testing.allocator;
    const result = try findSkill(allocator, "non-existent-skill-12345");
    try std.testing.expect(result == null);
}

test "formatBytes" {
    const allocator = std.testing.allocator;

    const b = try formatBytes(allocator, 500);
    defer allocator.free(b);
    try std.testing.expectEqualStrings("500 B", b);

    const kb = try formatBytes(allocator, 2048);
    defer allocator.free(kb);
    try std.testing.expect(std.mem.indexOf(u8, kb, "KB") != null);

    const mb = try formatBytes(allocator, 1024 * 1024 * 5);
    defer allocator.free(mb);
    try std.testing.expect(std.mem.indexOf(u8, mb, "MB") != null);
}
