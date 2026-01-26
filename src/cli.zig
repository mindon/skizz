const std = @import("std");
const types = @import("types.zig");
const io_helper = @import("io_helper.zig");
const list_cmd = @import("commands/list.zig");
const read_cmd = @import("commands/read.zig");
const install_cmd = @import("commands/install.zig");
const remove_cmd = @import("commands/remove.zig");
const sync_cmd = @import("commands/sync.zig");
const manage_cmd = @import("commands/manage.zig");

const version = "1.3.0";

// Global Io instance for utils
var global_io: std.Io = undefined;

pub fn getIo() std.Io {
    return global_io;
}

pub fn run(allocator: std.mem.Allocator, args: std.process.Args, io: std.Io) !void {
    // Store io globally for utils to access
    global_io = io;

    var it = try std.process.Args.Iterator.initAllocator(args, allocator);
    defer it.deinit();

    // Skip the program name
    _ = it.next();

    const cmd_arg = it.next() orelse {
        printHelp();
        return;
    };

    const command = parseCommand(cmd_arg);

    // Collect remaining args
    var cmd_args = std.ArrayList([]const u8){};
    defer cmd_args.deinit(allocator);
    while (it.next()) |arg| {
        try cmd_args.append(allocator, arg);
    }

    switch (command) {
        .list => try list_cmd.execute(allocator, io),
        .install => try install_cmd.execute(allocator, io, cmd_args.items),
        .read => try read_cmd.execute(allocator, io, cmd_args.items),
        .sync => try sync_cmd.execute(allocator, io, cmd_args.items),
        .manage => try manage_cmd.execute(allocator, io),
        .remove => try remove_cmd.execute(allocator, io, cmd_args.items),
        .help => printHelp(),
        .version => printVersion(),
        .unknown => {
            io_helper.printErr("{s}Error:{s} Unknown command: {s}\n", .{ types.Color.red, types.Color.reset, cmd_arg });
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

    io_helper.print("\n{s}{s}skizz{s} - Universal skills loader for AI coding agents\n", .{ C.bold, C.cyan, C.reset });
    io_helper.print("\n{s}USAGE:{s}\n", .{ C.yellow, C.reset });
    io_helper.print("  skizz <command> [options]\n", .{});
    io_helper.print("\n{s}COMMANDS:{s}\n", .{ C.yellow, C.reset });
    io_helper.print("  {s}list{s}              List all installed skills\n", .{ C.green, C.reset });
    io_helper.print("  {s}install{s} <source>  Install skills from GitHub or local path\n", .{ C.green, C.reset });
    io_helper.print("  {s}read{s} <name>       Read skill content to stdout (for AI agents)\n", .{ C.green, C.reset });
    io_helper.print("  {s}sync{s}              Update AGENTS.md with installed skills\n", .{ C.green, C.reset });
    io_helper.print("  {s}manage{s}            Interactively manage (remove) installed skills\n", .{ C.green, C.reset });
    io_helper.print("  {s}remove{s} <name>     Remove a specific skill\n", .{ C.green, C.reset });
    io_helper.print("\n{s}OPTIONS:{s}\n", .{ C.yellow, C.reset });
    io_helper.print("  {s}-g, --global{s}      Install globally (default: project)\n", .{ C.cyan, C.reset });
    io_helper.print("  {s}-u, --universal{s}   Install to .agent/skills/ (for AGENTS.md)\n", .{ C.cyan, C.reset });
    io_helper.print("  {s}-y, --yes{s}         Skip interactive selection\n", .{ C.cyan, C.reset });
    io_helper.print("  {s}-o, --output{s}      Output file path (default: AGENTS.md)\n", .{ C.cyan, C.reset });
    io_helper.print("\n{s}EXAMPLES:{s}\n", .{ C.yellow, C.reset });
    io_helper.print("  skizz install anthropics/skills\n", .{});
    io_helper.print("  skizz install owner/repo --global\n", .{});
    io_helper.print("  skizz install ./local/skill\n", .{});
    io_helper.print("  skizz sync\n", .{});
    io_helper.print("  skizz read my-skill\n", .{});
    io_helper.print("\n{s}VERSION:{s} {s}\n\n", .{ C.yellow, C.reset, version });
}

fn printVersion() void {
    io_helper.print("skizz v{s}\n", .{version});
}

test "parseCommand" {
    try std.testing.expectEqual(types.Command.list, parseCommand("list"));
    try std.testing.expectEqual(types.Command.list, parseCommand("ls"));
    try std.testing.expectEqual(types.Command.install, parseCommand("install"));
    try std.testing.expectEqual(types.Command.remove, parseCommand("rm"));
    try std.testing.expectEqual(types.Command.unknown, parseCommand("invalid"));
}
