const std = @import("std");
const types = @import("types.zig");
const io = @import("io_helper.zig");
const list_cmd = @import("commands/list.zig");
const read_cmd = @import("commands/read.zig");
const install_cmd = @import("commands/install.zig");
const remove_cmd = @import("commands/remove.zig");
const sync_cmd = @import("commands/sync.zig");
const manage_cmd = @import("commands/manage.zig");

const version = "1.3.0";

pub fn run(allocator: std.mem.Allocator) !void {
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        printHelp();
        return;
    }

    const command = parseCommand(args[1]);
    const cmd_args = if (args.len > 2) args[2..] else &[_][]const u8{};

    switch (command) {
        .list => try list_cmd.execute(allocator),
        .install => try install_cmd.execute(allocator, cmd_args),
        .read => try read_cmd.execute(allocator, cmd_args),
        .sync => try sync_cmd.execute(allocator, cmd_args),
        .manage => try manage_cmd.execute(allocator),
        .remove => try remove_cmd.execute(allocator, cmd_args),
        .help => printHelp(),
        .version => printVersion(),
        .unknown => {
            io.printErr("{s}Error:{s} Unknown command: {s}\n", .{ types.Color.red, types.Color.reset, args[1] });
            printHelp();
            std.process.exit(1);
        },
    }
}

fn parseCommand(arg: []const u8) types.Command {
    const commands = std.StaticStringMap(types.Command).initComptime(.{
        .{ "list", .list },
        .{ "ls", .list },
        .{ "install", .install },
        .{ "i", .install },
        .{ "read", .read },
        .{ "sync", .sync },
        .{ "manage", .manage },
        .{ "remove", .remove },
        .{ "rm", .remove },
        .{ "help", .help },
        .{ "-h", .help },
        .{ "--help", .help },
        .{ "version", .version },
        .{ "-v", .version },
        .{ "--version", .version },
    });

    return commands.get(arg) orelse .unknown;
}

fn printHelp() void {
    const C = types.Color;

    io.print("\n{s}{s}skizz{s} - Universal skills loader for AI coding agents\n", .{ C.bold, C.cyan, C.reset });
    io.print("\n{s}USAGE:{s}\n", .{ C.yellow, C.reset });
    io.print("  skizz <command> [options]\n", .{});
    io.print("\n{s}COMMANDS:{s}\n", .{ C.yellow, C.reset });
    io.print("  {s}list{s}              List all installed skills\n", .{ C.green, C.reset });
    io.print("  {s}install{s} <source>  Install skills from GitHub or local path\n", .{ C.green, C.reset });
    io.print("  {s}read{s} <name>       Read skill content to stdout (for AI agents)\n", .{ C.green, C.reset });
    io.print("  {s}sync{s}              Update AGENTS.md with installed skills\n", .{ C.green, C.reset });
    io.print("  {s}manage{s}            Interactively manage (remove) installed skills\n", .{ C.green, C.reset });
    io.print("  {s}remove{s} <name>     Remove a specific skill\n", .{ C.green, C.reset });
    io.print("\n{s}OPTIONS:{s}\n", .{ C.yellow, C.reset });
    io.print("  {s}-g, --global{s}      Install globally (default: project)\n", .{ C.cyan, C.reset });
    io.print("  {s}-u, --universal{s}   Install to .agent/skills/ (for AGENTS.md)\n", .{ C.cyan, C.reset });
    io.print("  {s}-y, --yes{s}         Skip interactive selection\n", .{ C.cyan, C.reset });
    io.print("  {s}-o, --output{s}      Output file path (default: AGENTS.md)\n", .{ C.cyan, C.reset });
    io.print("\n{s}EXAMPLES:{s}\n", .{ C.yellow, C.reset });
    io.print("  skizz install anthropics/skills\n", .{});
    io.print("  skizz install owner/repo --global\n", .{});
    io.print("  skizz install ./local/skill\n", .{});
    io.print("  skizz sync\n", .{});
    io.print("  skizz read my-skill\n", .{});
    io.print("\n{s}VERSION:{s} {s}\n\n", .{ C.yellow, C.reset, version });
}

fn printVersion() void {
    io.print("skizz v{s}\n", .{version});
}

test "parseCommand" {
    try std.testing.expectEqual(types.Command.list, parseCommand("list"));
    try std.testing.expectEqual(types.Command.list, parseCommand("ls"));
    try std.testing.expectEqual(types.Command.install, parseCommand("install"));
    try std.testing.expectEqual(types.Command.remove, parseCommand("rm"));
    try std.testing.expectEqual(types.Command.unknown, parseCommand("invalid"));
}
