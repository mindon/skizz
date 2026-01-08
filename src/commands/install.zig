const std = @import("std");
const types = @import("../types.zig");
const skills_util = @import("../utils/skills.zig");
const dirs = @import("../utils/dirs.zig");
const yaml = @import("../utils/yaml.zig");
const git = @import("../utils/git.zig");
const io = @import("../io_helper.zig");

const Color = types.Color;

/// Execute the install command
pub fn execute(allocator: std.mem.Allocator, args: []const []const u8) !void {
    // Parse options
    var options = types.InstallOptions{};
    var source: ?[]const u8 = null;

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "-g") or std.mem.eql(u8, arg, "--global")) {
            options.global = true;
        } else if (std.mem.eql(u8, arg, "-u") or std.mem.eql(u8, arg, "--universal")) {
            options.universal = true;
        } else if (std.mem.eql(u8, arg, "-y") or std.mem.eql(u8, arg, "--yes")) {
            options.yes = true;
        } else if (arg[0] != '-') {
            source = arg;
        }
    }

    if (source == null) {
        io.printErr("{s}Error:{s} Missing source\n", .{ Color.red, Color.reset });
        io.printErr("\nUsage: skizz install <source> [options]\n", .{});
        io.printErr("\nExamples:\n", .{});
        io.printErr("  skizz install anthropics/skills\n", .{});
        io.printErr("  skizz install owner/repo --global\n", .{});
        io.printErr("  skizz install ./local/skill\n", .{});
        std.process.exit(1);
    }

    const src = source.?;

    // Determine target directory
    const target_dir = try dirs.getSkillsDir(allocator, !options.global, options.universal);
    defer allocator.free(target_dir);

    // Ensure target directory exists
    try dirs.ensureDir(target_dir);

    if (dirs.isLocalPath(src)) {
        try installFromLocal(allocator, src, target_dir, options);
    } else {
        try installFromGit(allocator, src, target_dir, options);
    }

    io.print("\n{s}✓{s} Installation complete!\n", .{ Color.green, Color.reset });
    io.print("  Run {s}skizz sync{s} to update AGENTS.md\n\n", .{ Color.cyan, Color.reset });
}

/// Install from local path
fn installFromLocal(
    allocator: std.mem.Allocator,
    source: []const u8,
    target_dir: []const u8,
    options: types.InstallOptions,
) !void {
    // Expand path
    const expanded = try dirs.expandPath(allocator, source);
    defer allocator.free(expanded);

    // Get absolute path
    const abs_path = if (std.fs.path.isAbsolute(expanded))
        try allocator.dupe(u8, expanded)
    else blk: {
        const cwd = try std.process.getCwdAlloc(allocator);
        defer allocator.free(cwd);
        break :blk try std.fs.path.join(allocator, &.{ cwd, expanded });
    };
    defer allocator.free(abs_path);

    // Check if it's a directory with SKILL.md
    const skill_path = try std.fs.path.join(allocator, &.{ abs_path, "SKILL.md" });
    defer allocator.free(skill_path);

    if (!dirs.fileExists(skill_path)) {
        io.printErr("{s}Error:{s} No SKILL.md found in {s}\n", .{ Color.red, Color.reset, abs_path });
        std.process.exit(1);
    }

    // Get skill name from directory
    const skill_name = std.fs.path.basename(abs_path);

    // Check for conflicts
    const dest_path = try std.fs.path.join(allocator, &.{ target_dir, skill_name });
    defer allocator.free(dest_path);

    if (dirs.dirExists(dest_path)) {
        if (!options.yes) {
            io.print("{s}Warning:{s} Skill '{s}' already exists. Overwriting.\n", .{
                Color.yellow,
                Color.reset,
                skill_name,
            });
        }
        try skills_util.removeDir(dest_path);
    }

    // Copy skill directory
    io.print("Installing {s}{s}{s}...\n", .{ Color.bold, skill_name, Color.reset });
    try skills_util.copyDir(allocator, abs_path, dest_path);

    io.print("  {s}→{s} {s}\n", .{ Color.green, Color.reset, dest_path });
}

/// Install from Git repository
fn installFromGit(
    allocator: std.mem.Allocator,
    source: []const u8,
    target_dir: []const u8,
    options: types.InstallOptions,
) !void {
    // Check if git is available
    if (!git.isGitAvailable(allocator)) {
        io.printErr("{s}Error:{s} Git is not available. Please install git.\n", .{ Color.red, Color.reset });
        std.process.exit(1);
    }

    io.print("Cloning repository...\n", .{});

    // Clone the repository
    const repo_path = git.cloneRepo(allocator, source) catch |err| {
        io.printErr("{s}Error:{s} Failed to clone repository: {any}\n", .{ Color.red, Color.reset, err });
        std.process.exit(1);
    };
    defer {
        skills_util.removeDir(repo_path) catch {};
        allocator.free(repo_path);
    }

    // Check for specific subpath
    const subpath = try git.extractSubpath(allocator, source);
    defer if (subpath) |p| allocator.free(p);

    if (subpath) |path| {
        // Install specific skill
        try installSpecificSkill(allocator, repo_path, path, target_dir, options);
    } else {
        // Find all skills in repo
        try installFromRepo(allocator, repo_path, target_dir, options);
    }
}

/// Install a specific skill from a cloned repo
fn installSpecificSkill(
    allocator: std.mem.Allocator,
    repo_path: []const u8,
    skill_path: []const u8,
    target_dir: []const u8,
    options: types.InstallOptions,
) !void {
    const full_path = try std.fs.path.join(allocator, &.{ repo_path, skill_path });
    defer allocator.free(full_path);

    const skill_file = try std.fs.path.join(allocator, &.{ full_path, "SKILL.md" });
    defer allocator.free(skill_file);

    if (!dirs.fileExists(skill_file)) {
        io.printErr("{s}Error:{s} No SKILL.md found at {s}\n", .{ Color.red, Color.reset, skill_path });
        std.process.exit(1);
    }

    const skill_name = std.fs.path.basename(skill_path);
    const dest_path = try std.fs.path.join(allocator, &.{ target_dir, skill_name });
    defer allocator.free(dest_path);

    if (dirs.dirExists(dest_path)) {
        if (!options.yes) {
            io.print("{s}Warning:{s} Skill '{s}' already exists. Overwriting.\n", .{
                Color.yellow,
                Color.reset,
                skill_name,
            });
        }
        try skills_util.removeDir(dest_path);
    }

    io.print("Installing {s}{s}{s}...\n", .{ Color.bold, skill_name, Color.reset });
    try skills_util.copyDir(allocator, full_path, dest_path);
    io.print("  {s}→{s} {s}\n", .{ Color.green, Color.reset, dest_path });
}

/// Install skills from a cloned repository (interactive selection)
fn installFromRepo(
    allocator: std.mem.Allocator,
    repo_path: []const u8,
    target_dir: []const u8,
    options: types.InstallOptions,
) !void {
    // Find all SKILL.md files
    const skill_paths = try git.findSkillFiles(allocator, repo_path);
    defer {
        for (skill_paths) |p| allocator.free(p);
        allocator.free(skill_paths);
    }

    if (skill_paths.len == 0) {
        io.printErr("{s}Error:{s} No skills found in repository\n", .{ Color.red, Color.reset });
        std.process.exit(1);
    }

    io.print("\nFound {d} skill(s):\n", .{skill_paths.len});

    // Collect skill info
    var skill_infos: std.ArrayList(SkillInfo) = .empty;
    defer {
        for (skill_infos.items) |info| {
            allocator.free(info.name);
            allocator.free(info.description);
            allocator.free(info.path);
            allocator.free(info.size_str);
        }
        skill_infos.deinit(allocator);
    }

    for (skill_paths) |rel_path| {
        const full_path = try std.fs.path.join(allocator, &.{ repo_path, rel_path });
        defer allocator.free(full_path);

        const skill_file = try std.fs.path.join(allocator, &.{ full_path, "SKILL.md" });
        defer allocator.free(skill_file);

        const content = skills_util.readFileAlloc(allocator, skill_file) catch continue;
        defer allocator.free(content);

        const name = std.fs.path.basename(rel_path);
        const description = try yaml.extractYamlField(allocator, content, "description");
        const size = skills_util.getDirSize(allocator, full_path) catch 0;
        const size_str = try skills_util.formatBytes(allocator, size);

        try skill_infos.append(allocator, .{
            .name = try allocator.dupe(u8, name),
            .description = description,
            .path = try allocator.dupe(u8, rel_path),
            .size_str = size_str,
        });
    }

    // Display skills
    for (skill_infos.items, 0..) |info, idx| {
        io.print("  {d}. {s}{s}{s} ({s})\n", .{
            idx + 1,
            Color.bold,
            info.name,
            Color.reset,
            info.size_str,
        });
        if (info.description.len > 0) {
            io.print("     {s}{s}{s}\n", .{ Color.gray, info.description, Color.reset });
        }
    }

    // Select skills to install
    var selected_buf: [64]usize = undefined;
    var selected_count: usize = 0;

    if (options.yes) {
        // Install all
        for (0..skill_infos.items.len) |idx| {
            if (selected_count < selected_buf.len) {
                selected_buf[selected_count] = idx;
                selected_count += 1;
            }
        }
    } else {
        // Interactive selection
        io.print("\nEnter skill numbers to install (comma-separated, or 'all'): ", .{});

        var input_buf: [256]u8 = undefined;
        const input = io.readLine(&input_buf) orelse {
            io.print("\n{s}Cancelled.{s}\n", .{ Color.yellow, Color.reset });
            return;
        };

        const trimmed = std.mem.trim(u8, input, " \t\r\n");

        if (trimmed.len == 0) {
            io.print("{s}No skills selected.{s}\n", .{ Color.yellow, Color.reset });
            return;
        }

        if (std.mem.eql(u8, trimmed, "all")) {
            for (0..skill_infos.items.len) |idx| {
                if (selected_count < selected_buf.len) {
                    selected_buf[selected_count] = idx;
                    selected_count += 1;
                }
            }
        } else {
            var parts = std.mem.splitAny(u8, trimmed, ", ");
            while (parts.next()) |part| {
                const num_str = std.mem.trim(u8, part, " ");
                if (num_str.len == 0) continue;

                const num = std.fmt.parseInt(usize, num_str, 10) catch continue;
                if (num >= 1 and num <= skill_infos.items.len) {
                    if (selected_count < selected_buf.len) {
                        selected_buf[selected_count] = num - 1;
                        selected_count += 1;
                    }
                }
            }

            if (selected_count == 0) {
                io.print("{s}No valid skills selected.{s}\n", .{ Color.yellow, Color.reset });
                return;
            }
        }
    }

    const selected = selected_buf[0..selected_count];

    // Install selected skills
    io.print("\n", .{});
    for (selected) |idx| {
        const info = skill_infos.items[idx];

        const full_path = try std.fs.path.join(allocator, &.{ repo_path, info.path });
        defer allocator.free(full_path);

        const dest_path = try std.fs.path.join(allocator, &.{ target_dir, info.name });
        defer allocator.free(dest_path);

        if (dirs.dirExists(dest_path)) {
            try skills_util.removeDir(dest_path);
        }

        io.print("Installing {s}{s}{s}...\n", .{ Color.bold, info.name, Color.reset });
        try skills_util.copyDir(allocator, full_path, dest_path);
        io.print("  {s}→{s} {s}\n", .{ Color.green, Color.reset, dest_path });
    }
}

const SkillInfo = struct {
    name: []const u8,
    description: []const u8,
    path: []const u8,
    size_str: []const u8,
};

test "install command parsing" {
    // Test option parsing logic
    var options = types.InstallOptions{};
    const args = [_][]const u8{ "-g", "--universal", "-y", "owner/repo" };

    for (args) |arg| {
        if (std.mem.eql(u8, arg, "-g") or std.mem.eql(u8, arg, "--global")) {
            options.global = true;
        } else if (std.mem.eql(u8, arg, "-u") or std.mem.eql(u8, arg, "--universal")) {
            options.universal = true;
        } else if (std.mem.eql(u8, arg, "-y") or std.mem.eql(u8, arg, "--yes")) {
            options.yes = true;
        }
    }

    try std.testing.expect(options.global);
    try std.testing.expect(options.universal);
    try std.testing.expect(options.yes);
}
