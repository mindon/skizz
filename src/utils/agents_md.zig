const std = @import("std");
const types = @import("../types.zig");
const yaml = @import("yaml.zig");

const START_MARKER = "<!-- skizz:start -->";
const END_MARKER = "<!-- skizz:end -->";

/// Generate XML format skills section for AGENTS.md
pub fn generateSkillsXml(allocator: std.mem.Allocator, skills: []const types.Skill) ![]const u8 {
    var buffer: std.ArrayList(u8) = .empty;
    errdefer buffer.deinit(allocator);

    try buffer.appendSlice(allocator, START_MARKER);
    try buffer.appendSlice(allocator, "\n\n");
    try buffer.appendSlice(allocator, "<skills_instructions>\n");
    try buffer.appendSlice(allocator, "When users ask you to perform tasks, check if any of the available skills below can help complete the task more effectively. Skills provide specialized capabilities and domain knowledge.\n\n");
    try buffer.appendSlice(allocator, "How to use skills:\n");
    try buffer.appendSlice(allocator, "- Read skills using: skizz read <skill-name>\n");
    try buffer.appendSlice(allocator, "- The skill's prompt will provide detailed instructions on how to complete the task\n\n");
    try buffer.appendSlice(allocator, "<available_skills>\n");

    for (skills) |skill| {
        try buffer.appendSlice(allocator, "<skill>\n");

        // Name
        try buffer.appendSlice(allocator, "  <name>");
        try buffer.appendSlice(allocator, skill.name);
        try buffer.appendSlice(allocator, "</name>\n");

        // Description
        try buffer.appendSlice(allocator, "  <description>");
        try buffer.appendSlice(allocator, skill.description);
        try buffer.appendSlice(allocator, "</description>\n");

        // Location
        try buffer.appendSlice(allocator, "  <location>");
        try buffer.appendSlice(allocator, skill.location.toString());
        try buffer.appendSlice(allocator, "</location>\n");

        try buffer.appendSlice(allocator, "</skill>\n");
    }

    try buffer.appendSlice(allocator, "</available_skills>\n");
    try buffer.appendSlice(allocator, "</skills_instructions>\n\n");
    try buffer.appendSlice(allocator, END_MARKER);

    return try buffer.toOwnedSlice(allocator);
}

/// Replace or insert skills section in AGENTS.md content
pub fn replaceSkillsSection(allocator: std.mem.Allocator, content: []const u8, new_section: []const u8) ![]const u8 {
    // Find existing markers
    const start_idx = std.mem.indexOf(u8, content, START_MARKER);
    const end_idx = std.mem.indexOf(u8, content, END_MARKER);

    if (start_idx != null and end_idx != null) {
        // Replace existing section
        const before = content[0..start_idx.?];
        const after = content[end_idx.? + END_MARKER.len ..];

        return try std.mem.concat(allocator, u8, &.{ before, new_section, after });
    } else {
        // Append new section
        if (content.len == 0) {
            return try allocator.dupe(u8, new_section);
        }

        // Add newlines if content doesn't end with them
        var suffix: []const u8 = "";
        if (content.len > 0 and content[content.len - 1] != '\n') {
            suffix = "\n\n";
        } else if (content.len > 1 and content[content.len - 2] != '\n') {
            suffix = "\n";
        }

        return try std.mem.concat(allocator, u8, &.{ content, suffix, new_section, "\n" });
    }
}

/// Remove skills section from content
pub fn removeSkillsSection(allocator: std.mem.Allocator, content: []const u8) ![]const u8 {
    const start_idx = std.mem.indexOf(u8, content, START_MARKER);
    const end_idx = std.mem.indexOf(u8, content, END_MARKER);

    if (start_idx != null and end_idx != null) {
        const before = content[0..start_idx.?];
        var after = content[end_idx.? + END_MARKER.len ..];

        // Trim leading newlines from after
        while (after.len > 0 and (after[0] == '\n' or after[0] == '\r')) {
            after = after[1..];
        }

        // Trim trailing newlines from before
        var before_trimmed = before;
        while (before_trimmed.len > 0 and
            (before_trimmed[before_trimmed.len - 1] == '\n' or
                before_trimmed[before_trimmed.len - 1] == '\r'))
        {
            before_trimmed = before_trimmed[0 .. before_trimmed.len - 1];
        }

        if (before_trimmed.len == 0 and after.len == 0) {
            return try allocator.dupe(u8, "");
        }

        if (after.len == 0) {
            return try std.mem.concat(allocator, u8, &.{ before_trimmed, "\n" });
        }

        return try std.mem.concat(allocator, u8, &.{ before_trimmed, "\n\n", after });
    }

    return try allocator.dupe(u8, content);
}

/// Check if a skill is currently in the AGENTS.md content
pub fn isSkillInContent(content: []const u8, skill_name: []const u8) bool {
    // Look for <name>skill_name</name> pattern
    var search_buf: [256]u8 = undefined;
    const search = std.fmt.bufPrint(&search_buf, "<name>{s}</name>", .{skill_name}) catch return false;
    return std.mem.indexOf(u8, content, search) != null;
}

/// Get list of skills currently in AGENTS.md
pub fn getSkillsInContent(allocator: std.mem.Allocator, content: []const u8) ![][]const u8 {
    var skills: std.ArrayList([]const u8) = .empty;
    errdefer {
        for (skills.items) |s| allocator.free(s);
        skills.deinit(allocator);
    }

    var pos: usize = 0;
    const name_start = "<name>";
    const name_end = "</name>";

    while (pos < content.len) {
        const start = std.mem.indexOfPos(u8, content, pos, name_start) orelse break;
        const end = std.mem.indexOfPos(u8, content, start, name_end) orelse break;

        const name = content[start + name_start.len .. end];
        try skills.append(allocator, try allocator.dupe(u8, name));

        pos = end + name_end.len;
    }

    return try skills.toOwnedSlice(allocator);
}

test "generateSkillsXml" {
    const allocator = std.testing.allocator;

    const skills = [_]types.Skill{
        .{
            .name = "test-skill",
            .description = "A test skill",
            .location = .project,
            .path = "/path/to/skill",
        },
    };

    const xml = try generateSkillsXml(allocator, &skills);
    defer allocator.free(xml);

    try std.testing.expect(std.mem.indexOf(u8, xml, START_MARKER) != null);
    try std.testing.expect(std.mem.indexOf(u8, xml, END_MARKER) != null);
    try std.testing.expect(std.mem.indexOf(u8, xml, "<name>test-skill</name>") != null);
}

test "replaceSkillsSection" {
    const allocator = std.testing.allocator;

    const content = "# Header\n\nSome content\n";
    const new_section = "<!-- skizz:start -->\nNew content\n<!-- skizz:end -->";

    const result = try replaceSkillsSection(allocator, content, new_section);
    defer allocator.free(result);

    try std.testing.expect(std.mem.indexOf(u8, result, "# Header") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "New content") != null);
}

test "isSkillInContent" {
    const content = "<available_skills>\n<skill>\n<name>my-skill</name>\n</skill>\n</available_skills>";
    try std.testing.expect(isSkillInContent(content, "my-skill"));
    try std.testing.expect(!isSkillInContent(content, "other-skill"));
}
