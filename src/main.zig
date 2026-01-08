const std = @import("std");
const cli = @import("cli.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    try cli.run(allocator);
}

test "main module" {
    _ = @import("cli.zig");
    _ = @import("types.zig");
    _ = @import("io_helper.zig");
    _ = @import("utils/dirs.zig");
    _ = @import("utils/yaml.zig");
    _ = @import("utils/skills.zig");
    _ = @import("utils/agents_md.zig");
    _ = @import("utils/git.zig");
    _ = @import("commands/list.zig");
    _ = @import("commands/read.zig");
    _ = @import("commands/install.zig");
    _ = @import("commands/remove.zig");
    _ = @import("commands/sync.zig");
    _ = @import("commands/manage.zig");
}
