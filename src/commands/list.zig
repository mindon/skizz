const std = @import("std");
const types = @import("../types.zig");
const skills_util = @import("../utils/skills.zig");
const io = @import("../io_helper.zig");

const Color = types.Color;

/// Execute the list command - shows all installed skills
pub fn execute(allocator: std.mem.Allocator) !void {
    const skills = try skills_util.findAllSkills(allocator);
    defer skills_util.freeSkills(allocator, skills);

    if (skills.len == 0) {
        io.print("\n{s}No skills installed.{s}\n\n", .{ Color.yellow, Color.reset });
        io.print("Install skills:\n", .{});
        io.print("  {s}skizz install anthropics/skills{s}      # Install to project\n", .{ Color.cyan, Color.reset });
        io.print("  {s}skizz install owner/skill --global{s}   # Install globally\n\n", .{ Color.cyan, Color.reset });
        return;
    }

    // Sort skills: project first, then by name
    std.mem.sort(types.Skill, skills, {}, compareSkills);

    // Calculate max name length for alignment
    var max_name_len: usize = 0;
    for (skills) |skill| {
        if (skill.name.len > max_name_len) {
            max_name_len = skill.name.len;
        }
    }

    io.print("\n{s}Installed Skills:{s}\n\n", .{ Color.bold, Color.reset });

    var project_count: usize = 0;
    var global_count: usize = 0;

    for (skills) |skill| {
        // Print name with padding
        io.print("  {s}{s}{s}", .{ Color.bold, skill.name, Color.reset });

        // Padding
        const padding = max_name_len - skill.name.len + 2;
        for (0..padding) |_| {
            io.print(" ", .{});
        }

        // Location badge
        switch (skill.location) {
            .project => {
                io.print("{s}(project){s}", .{ Color.blue, Color.reset });
                project_count += 1;
            },
            .global => {
                io.print("{s}(global){s}", .{ Color.gray, Color.reset });
                global_count += 1;
            },
        }
        io.print("\n", .{});

        // Description
        if (skill.description.len > 0) {
            io.print("    {s}{s}{s}\n", .{ Color.gray, skill.description, Color.reset });
        }
    }

    // Summary
    io.print("\n{s}Total:{s} {d} skill(s)", .{ Color.dim, Color.reset, skills.len });
    if (project_count > 0) {
        io.print(" ({d} project", .{project_count});
        if (global_count > 0) {
            io.print(", {d} global", .{global_count});
        }
        io.print(")", .{});
    } else if (global_count > 0) {
        io.print(" ({d} global)", .{global_count});
    }
    io.print("\n\n", .{});
}

fn compareSkills(_: void, a: types.Skill, b: types.Skill) bool {
    // Project skills come first
    if (a.location != b.location) {
        return a.location == .project;
    }
    // Then sort by name
    return std.mem.lessThan(u8, a.name, b.name);
}

test "compareSkills" {
    const skill_a = types.Skill{
        .name = "alpha",
        .description = "",
        .location = .project,
        .path = "",
    };
    const skill_b = types.Skill{
        .name = "beta",
        .description = "",
        .location = .global,
        .path = "",
    };
    const skill_c = types.Skill{
        .name = "gamma",
        .description = "",
        .location = .project,
        .path = "",
    };

    // Project should come before global
    try std.testing.expect(compareSkills({}, skill_a, skill_b));
    try std.testing.expect(!compareSkills({}, skill_b, skill_a));

    // Same location: sort by name
    try std.testing.expect(compareSkills({}, skill_a, skill_c));
}
