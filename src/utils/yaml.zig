const std = @import("std");

/// Extract a field value from YAML frontmatter
/// Returns the value or empty string if not found
pub fn extractYamlField(allocator: std.mem.Allocator, content: []const u8, field: []const u8) ![]const u8 {
    // Find the frontmatter section (between --- markers)
    const frontmatter = extractFrontmatter(content) orelse return try allocator.dupe(u8, "");

    // Search for the field in the frontmatter
    var lines = std.mem.splitScalar(u8, frontmatter, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0) continue;

        // Check if line starts with field:
        if (std.mem.startsWith(u8, trimmed, field)) {
            const rest = trimmed[field.len..];
            if (rest.len > 0 and rest[0] == ':') {
                const value = std.mem.trim(u8, rest[1..], " \t\r");
                // Remove quotes if present
                if (value.len >= 2) {
                    if ((value[0] == '"' and value[value.len - 1] == '"') or
                        (value[0] == '\'' and value[value.len - 1] == '\''))
                    {
                        return try allocator.dupe(u8, value[1 .. value.len - 1]);
                    }
                }
                return try allocator.dupe(u8, value);
            }
        }
    }

    return try allocator.dupe(u8, "");
}

/// Check if content has valid YAML frontmatter (starts with ---)
pub fn hasValidFrontmatter(content: []const u8) bool {
    const trimmed = std.mem.trimLeft(u8, content, " \t\r\n");
    return std.mem.startsWith(u8, trimmed, "---");
}

/// Extract the frontmatter section from content
fn extractFrontmatter(content: []const u8) ?[]const u8 {
    const trimmed = std.mem.trimLeft(u8, content, " \t\r\n");
    if (!std.mem.startsWith(u8, trimmed, "---")) return null;

    // Find the closing ---
    const after_first = trimmed[3..];
    const start = std.mem.indexOf(u8, after_first, "\n") orelse return null;
    const rest = after_first[start + 1 ..];

    // Find the end marker
    if (std.mem.indexOf(u8, rest, "\n---")) |end| {
        return rest[0..end];
    }

    return null;
}

/// Parse all fields from YAML frontmatter into a hash map
pub fn parseFrontmatter(allocator: std.mem.Allocator, content: []const u8) !std.StringHashMap([]const u8) {
    var map = std.StringHashMap([]const u8).init(allocator);
    errdefer {
        var it = map.iterator();
        while (it.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            allocator.free(entry.value_ptr.*);
        }
        map.deinit();
    }

    const frontmatter = extractFrontmatter(content) orelse return map;

    var lines = std.mem.splitScalar(u8, frontmatter, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0) continue;

        // Find the colon separator
        if (std.mem.indexOf(u8, trimmed, ":")) |colon_idx| {
            const key = std.mem.trim(u8, trimmed[0..colon_idx], " \t");
            var value = std.mem.trim(u8, trimmed[colon_idx + 1 ..], " \t");

            // Remove quotes if present
            if (value.len >= 2) {
                if ((value[0] == '"' and value[value.len - 1] == '"') or
                    (value[0] == '\'' and value[value.len - 1] == '\''))
                {
                    value = value[1 .. value.len - 1];
                }
            }

            const key_copy = try allocator.dupe(u8, key);
            errdefer allocator.free(key_copy);
            const value_copy = try allocator.dupe(u8, value);

            try map.put(key_copy, value_copy);
        }
    }

    return map;
}

/// Get content after frontmatter (the actual markdown body)
pub fn getBodyContent(content: []const u8) []const u8 {
    const trimmed = std.mem.trimLeft(u8, content, " \t\r\n");
    if (!std.mem.startsWith(u8, trimmed, "---")) return content;

    // Find the closing ---
    const after_first = trimmed[3..];
    if (std.mem.indexOf(u8, after_first, "\n---")) |end| {
        const after_end = after_first[end + 4 ..];
        // Skip the newline after ---
        if (after_end.len > 0 and after_end[0] == '\n') {
            return after_end[1..];
        }
        return after_end;
    }

    return content;
}

test "extractYamlField" {
    const allocator = std.testing.allocator;

    const content =
        \\---
        \\name: test-skill
        \\description: A test skill
        \\version: 1.0.0
        \\---
        \\# Content
    ;

    const name = try extractYamlField(allocator, content, "name");
    defer allocator.free(name);
    try std.testing.expectEqualStrings("test-skill", name);

    const desc = try extractYamlField(allocator, content, "description");
    defer allocator.free(desc);
    try std.testing.expectEqualStrings("A test skill", desc);

    const missing = try extractYamlField(allocator, content, "missing");
    defer allocator.free(missing);
    try std.testing.expectEqualStrings("", missing);
}

test "hasValidFrontmatter" {
    try std.testing.expect(hasValidFrontmatter("---\nname: test\n---\n"));
    try std.testing.expect(hasValidFrontmatter("  ---\nname: test\n---\n"));
    try std.testing.expect(!hasValidFrontmatter("# No frontmatter"));
    try std.testing.expect(!hasValidFrontmatter(""));
}

test "getBodyContent" {
    const content =
        \\---
        \\name: test
        \\---
        \\# Body content here
    ;

    const body = getBodyContent(content);
    try std.testing.expect(std.mem.indexOf(u8, body, "# Body content here") != null);
}
