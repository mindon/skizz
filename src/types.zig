const std = @import("std");

/// Skill information structure
pub const Skill = struct {
    name: []const u8,
    description: []const u8,
    location: Location,
    path: []const u8,

    pub const Location = enum {
        project,
        global,

        pub fn toString(self: Location) []const u8 {
            return switch (self) {
                .project => "project",
                .global => "global",
            };
        }
    };
};

/// Skill location details
pub const SkillLocation = struct {
    path: []const u8,
    base_dir: []const u8,
    source: []const u8,
};

/// Install options
pub const InstallOptions = struct {
    global: bool = false,
    universal: bool = false,
    yes: bool = false,
};

/// Sync options
pub const SyncOptions = struct {
    yes: bool = false,
    output: ?[]const u8 = null,
};

/// Skill metadata from SKILL.md frontmatter
pub const SkillMetadata = struct {
    name: []const u8,
    description: []const u8,
    context: ?[]const u8 = null,
};

/// CLI command types
pub const Command = enum {
    list,
    install,
    read,
    sync,
    manage,
    remove,
    help,
    version,
    unknown,
};

/// ANSI color codes for terminal output
pub const Color = struct {
    pub const reset = "\x1b[0m";
    pub const bold = "\x1b[1m";
    pub const dim = "\x1b[2m";

    pub const red = "\x1b[31m";
    pub const green = "\x1b[32m";
    pub const yellow = "\x1b[33m";
    pub const blue = "\x1b[34m";
    pub const magenta = "\x1b[35m";
    pub const cyan = "\x1b[36m";
    pub const white = "\x1b[37m";
    pub const gray = "\x1b[90m";

    pub const bg_red = "\x1b[41m";
    pub const bg_green = "\x1b[42m";
    pub const bg_yellow = "\x1b[43m";
    pub const bg_blue = "\x1b[44m";
};

test "Skill.Location.toString" {
    try std.testing.expectEqualStrings("project", Skill.Location.project.toString());
    try std.testing.expectEqualStrings("global", Skill.Location.global.toString());
}
