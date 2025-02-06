const std = @import("std");
const cli = @import("./root.zig");

pub const FooBar = enum {
    hello,
    world,
};

pub const argument_defs: cli.ArgDefs = &.{
    .{
        .name = "foobar",
        .type = .{ .Enum = FooBar },
        .help = "Foobar :)",
    },
    .{
        .name = "sources",
        .positional = true,
        .type = .String,
        .help = "The path to the main orb file, typically called main.orb",
    },
    .{
        .name = "out_path",
        .long = "out",
        .short = 'o',
        .type = .String,
        .help = "The path to where the resulting executable should be saved",
    },
    .{
        .name = "opt_level",
        .long = "opt",
        .short = 'O',
        .type = .Uint,
        .default_value = .{ .Uint = 5 },
        .help = "The optimization level. Is a value between 0 and 3.",
    },
    .{
        .name = "libraries",
        .long = "libs",
        .short = 'l',
        .type = .{ .List = &.String },
        .help = "A list of space seperated paths to libraries that should be included",
    },
    .{
        .name = "stdlib",
        .long = "stdlib",
        .type = .String,
        .default_value = .{ .String = .{ .allocator = std.heap.page_allocator, .value = "/lib/orb/std/" } },
        .help = "The path to the orb standard library",
    },
    .{
        .name = "entry_spell",
        .long = "entry",
        .short = 'e',
        .type = .String,
        .help = "The spell in the main orb file, that starts the program",
    },
    .{
        .name = "debug",
        .long = "debug",
        .short = 'd',
        .default_value = .{ .Bool = false },
        .help = "Compile the program in debug mode",
    },
};

pub fn main() !void {
    var m = cli.Args(argument_defs).parseArgs(std.heap.page_allocator, .{}) catch |e| {
        std.log.err("Encountered goblin: {any}", .{e});
        return;
    };
    defer m.deinit();

    const arg_t: cli.ArgType = .{ .List = &.String };

    var val = arg_t.parseToValue(
        "stdlib funky_mr_baton clap el_mahico",
        .{},
        m.allocator,
    ) catch cli.ArgValue{ .Int = 5 };

    defer val.deinit();

    try cli.setField(
        argument_defs,
        &m,
        "libraries",
        val,
    );

    const enum_arg_t: cli.ArgType = .{ .Enum = FooBar };
    var enum_val = try enum_arg_t.parseToValue("world", m.conf, m.allocator);

    defer enum_val.deinit();

    try cli.setField(
        argument_defs,
        &m,
        "foobar",
        enum_val,
    );

    std.debug.print("New enum value: {}\n", .{m.args.foobar});

    std.debug.print("\nARGS:\n", .{});
    m.print();
}
