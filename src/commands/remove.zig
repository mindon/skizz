const std = @import("std");
const types = @import("../types.zig");
const skills_util = @import("../utils/skills.zig");
const dirs = @import("../utils/dirs.zig");
const io = @import("../io_helper.zig");

const Color = types.Color;

/// Execute the remove command - removes a specific skill
pub fn execute(allocator: std.mem.Allocator, args: []const []const u8) !void {
    if (args.len == 0) {
        io.printErr("{s}Error:{s} Missing skill name\n", .{ Color.red, Color.reset });
        io.printErr("\nUsage: skizz remove <skill-name>\n", .{});
        io.printErr("       skizz rm <skill-name>\n", .{});
        io.printErr("\nFor interactive removal, use: skizz manage\n", .{});
        std.process.exit(1);
    }

    const skill_name = args[0];

    const skill_loc = try skills_util.findSkill(allocator, skill_name);

    if (skill_loc == null) {
        io.printErr("{s}Error:{s} Skill '{s}' not found\n", .{ Color.red, Color.reset, skill_name });
        std.process.exit(1);
    }

    const loc = skill_loc.?;
    defer skills_util.freeSkillLocation(allocator, loc);

    // Determine if global or project
    const home = dirs.getHomeDir(allocator) catch "";
    defer if (home.len > 0) allocator.free(home);

    const location_str = if (home.len > 0 and std.mem.startsWith(u8, loc.source, home))
        "global"
    else
        "project";

    // Remove the skill directory
    skills_util.removeDir(loc.base_dir) catch |err| {
        io.printErr("{s}Error:{s} Failed to remove skill: {any}\n", .{ Color.red, Color.reset, err });
        std.process.exit(1);
    };

    io.print("{s}✓{s} Removed: {s}{s}{s}\n", .{
        Color.green,
        Color.reset,
        Color.bold,
        skill_name,
        Color.reset,
    });
    io.print("   From: {s} ({s})\n", .{ location_str, loc.source });
}

test "remove command" {
    // Test would require filesystem mocking
}
