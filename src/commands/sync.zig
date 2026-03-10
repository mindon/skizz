const std = @import("std");
const types = @import("../types.zig");
const skills_util = @import("../utils/skills.zig");
const agents_md = @import("../utils/agents_md.zig");
const dirs = @import("../utils/dirs.zig");
const io_helper = @import("../io_helper.zig");

const Color = types.Color;

/// Execute the sync command - updates AGENTS.md with installed skills
pub fn execute(allocator: std.mem.Allocator, io: std.Io, args: []const []const u8) !void {
    // Parse options
    var options = types.SyncOptions{};

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "-y") or std.mem.eql(u8, arg, "--yes")) {
            options.yes = true;
        } else if (std.mem.eql(u8, arg, "-o") or std.mem.eql(u8, arg, "--output")) {
            if (i + 1 < args.len) {
                i += 1;
                options.output = args[i];
            }
        }
    }

    // Get output file path
    const cwd = try std.process.currentPathAlloc(io, allocator);
    defer allocator.free(cwd);

    const output_file = if (options.output) |out|
        try std.fs.path.join(allocator, &.{ cwd, out })
    else
        try std.fs.path.join(allocator, &.{ cwd, "AGENTS.md" });
    defer allocator.free(output_file);

    // Validate output file extension
    if (!std.mem.endsWith(u8, output_file, ".md")) {
        io_helper.printErr("{s}Error:{s} Output file must be a .md file\n", .{ Color.red, Color.reset });
        std.process.exit(1);
    }

    // Get all installed skills
    const all_skills = try skills_util.findAllSkills(allocator);
    defer skills_util.freeSkills(allocator, all_skills);

    if (all_skills.len == 0) {
        io_helper.print("{s}No skills installed.{s}\n", .{ Color.yellow, Color.reset });
        io_helper.print("Install skills first: skizz install owner/repo\n", .{});
        return;
    }

    // Sort skills: project first, then by name
    std.mem.sort(types.Skill, all_skills, {}, compareSkills);

    // Read existing content
    const existing_content = skills_util.readFileAlloc(allocator, output_file) catch |err| switch (err) {
        error.FileNotFound => try allocator.dupe(u8, ""),
        else => return err,
    };
    defer allocator.free(existing_content);

    // Determine which skills to sync
    var selected_buf: [64]usize = undefined;
    var selected_count: usize = 0;

    if (options.yes) {
        // Sync all skills
        for (0..all_skills.len) |idx| {
            if (selected_count < selected_buf.len) {
                selected_buf[selected_count] = idx;
                selected_count += 1;
            }
        }
    } else {
        // Interactive selection
        io_helper.print("\n{s}Available skills:{s}\n\n", .{ Color.bold, Color.reset });

        for (all_skills, 0..) |skill, idx| {
            const in_file = agents_md.isSkillInContent(existing_content, skill.name);
            const marker = if (in_file) "[x]" else "[ ]";
            const location_str = if (skill.location == .project)
                Color.blue ++ "(project)" ++ Color.reset
            else
                Color.gray ++ "(global)" ++ Color.reset;

            io_helper.print("  {d}. {s} {s}{s}{s} {s}\n", .{
                idx + 1,
                marker,
                Color.bold,
                skill.name,
                Color.reset,
                location_str,
            });
            if (skill.description.len > 0) {
                io_helper.print("       {s}{s}{s}\n", .{ Color.gray, skill.description, Color.reset });
            }
        }

        io_helper.print("\nEnter skill numbers to sync (comma-separated, 'all', or 'none'): ", .{});

        var input_buf: [256]u8 = undefined;
        const input = io_helper.readLine(&input_buf) orelse {
            io_helper.printErr("\n{s}Cancelled.{s}\n", .{ Color.yellow, Color.reset });
            return;
        };

        const trimmed = std.mem.trim(u8, input, " \t\r\n");

        if (trimmed.len == 0 or std.mem.eql(u8, trimmed, "none")) {
            // Remove skills section
            const new_content = try agents_md.removeSkillsSection(allocator, existing_content);
            defer allocator.free(new_content);

            try skills_util.writeFile(output_file, new_content);
            io_helper.print("{s}✓{s} Skills section removed from {s}\n", .{
                Color.green,
                Color.reset,
                output_file,
            });
            return;
        }

        if (std.mem.eql(u8, trimmed, "all")) {
            for (0..all_skills.len) |idx| {
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
                if (num >= 1 and num <= all_skills.len) {
                    if (selected_count < selected_buf.len) {
                        selected_buf[selected_count] = num - 1;
                        selected_count += 1;
                    }
                }
            }

            if (selected_count == 0) {
                io_helper.print("{s}No valid skills selected.{s}\n", .{ Color.yellow, Color.reset });
                return;
            }
        }
    }

    // Build selected skills array
    var selected_skills: std.ArrayList(types.Skill) = .empty;
    defer selected_skills.deinit(allocator);

    for (selected_buf[0..selected_count]) |idx| {
        try selected_skills.append(allocator, all_skills[idx]);
    }

    // Generate new skills XML
    const skills_xml = try agents_md.generateSkillsXml(allocator, selected_skills.items);
    defer allocator.free(skills_xml);

    // Update content
    const new_content = try agents_md.replaceSkillsSection(allocator, existing_content, skills_xml);
    defer allocator.free(new_content);

    // Ensure parent directory exists
    if (std.fs.path.dirname(output_file)) |parent| {
        try dirs.ensureDir(parent);
    }

    // Write file
    try skills_util.writeFile(output_file, new_content);

    io_helper.print("\n{s}✓{s} Updated {s}\n", .{ Color.green, Color.reset, output_file });
    io_helper.print("  Synced {d} skill(s)\n\n", .{selected_count});
}

fn compareSkills(_: void, a: types.Skill, b: types.Skill) bool {
    if (a.location != b.location) {
        return a.location == .project;
    }
    return std.mem.lessThan(u8, a.name, b.name);
}

test "sync command option parsing" {
    var options = types.SyncOptions{};
    const args = [_][]const u8{ "-y", "-o", "custom.md" };

    var idx: usize = 0;
    while (idx < args.len) : (idx += 1) {
        const arg = args[idx];
        if (std.mem.eql(u8, arg, "-y")) {
            options.yes = true;
        } else if (std.mem.eql(u8, arg, "-o")) {
            if (idx + 1 < args.len) {
                idx += 1;
                options.output = args[idx];
            }
        }
    }

    try std.testing.expect(options.yes);
    try std.testing.expectEqualStrings("custom.md", options.output.?);
}
