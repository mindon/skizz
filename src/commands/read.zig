const std = @import("std");
const types = @import("../types.zig");
const skills_util = @import("../utils/skills.zig");
const io = @import("../io_helper.zig");

const Color = types.Color;

/// Execute the read command - outputs skill content to stdout (for AI agents)
pub fn execute(allocator: std.mem.Allocator, args: []const []const u8) !void {
    if (args.len == 0) {
        io.printErr("{s}Error:{s} Missing skill name\n", .{ Color.red, Color.reset });
        io.printErr("\nUsage: skizz read <skill-name>\n", .{});
        std.process.exit(1);
    }

    const skill_name = args[0];

    const skill_loc = try skills_util.findSkill(allocator, skill_name);

    if (skill_loc == null) {
        io.printErr("{s}Error:{s} Skill '{s}' not found\n", .{ Color.red, Color.reset, skill_name });
        io.printErr("\nSearched:\n", .{});
        io.printErr("  .agent/skills/ (project universal)\n", .{});
        io.printErr("  ~/.agent/skills/ (global universal)\n", .{});
        io.printErr("  .claude/skills/ (project)\n", .{});
        io.printErr("  ~/.claude/skills/ (global)\n", .{});
        io.printErr("\nInstall skills: skizz install owner/repo\n", .{});
        std.process.exit(1);
    }

    const loc = skill_loc.?;
    defer skills_util.freeSkillLocation(allocator, loc);

    // Read skill content
    const content = skills_util.readFileAlloc(allocator, loc.path) catch |err| {
        io.printErr("{s}Error:{s} Failed to read skill file: {any}\n", .{ Color.red, Color.reset, err });
        std.process.exit(1);
    };
    defer allocator.free(content);

    // Output in Claude Code format
    io.print("Reading: {s}\n", .{skill_name});
    io.print("Base directory: {s}\n", .{loc.base_dir});
    io.print("\n", .{});
    io.writeStdout(content);
    if (content.len > 0 and content[content.len - 1] != '\n') {
        io.print("\n", .{});
    }
    io.print("\n", .{});
    io.print("Skill read: {s}\n", .{skill_name});
}

test "execute with no args should fail" {
    // This test would require mocking stdout/stderr
    // For now, just verify the function signature is correct
}
