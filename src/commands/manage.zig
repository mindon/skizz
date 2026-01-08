const std = @import("std");
const types = @import("../types.zig");
const skills_util = @import("../utils/skills.zig");
const dirs = @import("../utils/dirs.zig");
const io = @import("../io_helper.zig");

const Color = types.Color;

/// Execute the manage command - interactively manage (remove) installed skills
pub fn execute(allocator: std.mem.Allocator) !void {
    // Get all installed skills
    const skills = try skills_util.findAllSkills(allocator);
    defer skills_util.freeSkills(allocator, skills);

    if (skills.len == 0) {
        io.print("{s}No skills installed.{s}\n", .{ Color.yellow, Color.reset });
        io.print("Install skills: skizz install owner/repo\n", .{});
        return;
    }

    // Sort skills: project first, then by name
    std.mem.sort(types.Skill, skills, {}, compareSkills);

    io.print("\n{s}Installed Skills:{s}\n\n", .{ Color.bold, Color.reset });

    // Display skills with numbers
    for (skills, 0..) |skill, idx| {
        const location_str = if (skill.location == .project)
            Color.blue ++ "(project)" ++ Color.reset
        else
            Color.gray ++ "(global)" ++ Color.reset;

        io.print("  {d}. {s}{s}{s} {s}\n", .{
            idx + 1,
            Color.bold,
            skill.name,
            Color.reset,
            location_str,
        });
        if (skill.description.len > 0) {
            io.print("     {s}{s}{s}\n", .{ Color.gray, skill.description, Color.reset });
        }
    }

    io.print("\nEnter skill numbers to remove (comma-separated), or 'q' to quit: ", .{});

    var input_buf: [256]u8 = undefined;
    const input = io.readLine(&input_buf) orelse {
        io.printErr("\n{s}Cancelled.{s}\n", .{ Color.yellow, Color.reset });
        return;
    };

    const trimmed = std.mem.trim(u8, input, " \t\r\n");

    if (trimmed.len == 0 or std.mem.eql(u8, trimmed, "q") or std.mem.eql(u8, trimmed, "quit")) {
        io.print("{s}No changes made.{s}\n", .{ Color.yellow, Color.reset });
        return;
    }

    // Parse selected indices
    var indices_buf: [64]usize = undefined;
    var indices_count: usize = 0;

    var parts = std.mem.splitAny(u8, trimmed, ", ");
    while (parts.next()) |part| {
        const num_str = std.mem.trim(u8, part, " ");
        if (num_str.len == 0) continue;

        const num = std.fmt.parseInt(usize, num_str, 10) catch continue;
        if (num >= 1 and num <= skills.len) {
            if (indices_count < indices_buf.len) {
                indices_buf[indices_count] = num - 1;
                indices_count += 1;
            }
        }
    }

    if (indices_count == 0) {
        io.print("{s}No valid skills selected.{s}\n", .{ Color.yellow, Color.reset });
        return;
    }

    const indices = indices_buf[0..indices_count];

    // Confirm removal
    io.print("\nYou are about to remove {d} skill(s):\n", .{indices_count});
    for (indices) |idx| {
        io.print("  - {s}\n", .{skills[idx].name});
    }
    io.print("\nContinue? [y/N]: ", .{});

    const confirm = io.readLine(&input_buf) orelse {
        io.printErr("\n{s}Cancelled.{s}\n", .{ Color.yellow, Color.reset });
        return;
    };

    const confirm_trimmed = std.mem.trim(u8, confirm, " \t\r\n");
    if (!std.mem.eql(u8, confirm_trimmed, "y") and !std.mem.eql(u8, confirm_trimmed, "Y") and
        !std.mem.eql(u8, confirm_trimmed, "yes"))
    {
        io.print("{s}Cancelled.{s}\n", .{ Color.yellow, Color.reset });
        return;
    }

    // Remove selected skills
    io.print("\n", .{});
    const home = dirs.getHomeDir(allocator) catch "";
    defer if (home.len > 0) allocator.free(home);

    for (indices) |idx| {
        const skill = skills[idx];

        // Find skill location
        const skill_loc = try skills_util.findSkill(allocator, skill.name);
        if (skill_loc == null) continue;

        const loc = skill_loc.?;
        defer skills_util.freeSkillLocation(allocator, loc);

        const location_str = if (home.len > 0 and std.mem.startsWith(u8, loc.source, home))
            "global"
        else
            "project";

        // Remove the skill
        skills_util.removeDir(loc.base_dir) catch |err| {
            io.printErr("{s}Error:{s} Failed to remove {s}: {any}\n", .{
                Color.red,
                Color.reset,
                skill.name,
                err,
            });
            continue;
        };

        io.print("{s}✓{s} Removed: {s}{s}{s}\n", .{
            Color.green,
            Color.reset,
            Color.bold,
            skill.name,
            Color.reset,
        });
        io.print("   From: {s} ({s})\n", .{ location_str, loc.source });
    }

    io.print("\n{s}Done!{s} Run {s}skizz sync{s} to update AGENTS.md\n\n", .{
        Color.green,
        Color.reset,
        Color.cyan,
        Color.reset,
    });
}

fn compareSkills(_: void, a: types.Skill, b: types.Skill) bool {
    if (a.location != b.location) {
        return a.location == .project;
    }
    return std.mem.lessThan(u8, a.name, b.name);
}

test "manage command" {
    // Interactive command - testing would require mocking stdin/stdout
}
