const std = @import("std");
const builtin = @import("builtin");

pub const ArgDefs = []const ArgDef;

pub const ArgType = union(enum) {
    Bool,
    Uint,
    Int,
    RangedInt: struct { min: i64, max: i64 },
    Float,
    String,
    Char,
    List: *const ArgType,
    Optional: *const ArgType,
    Enum: type,

    pub fn GetType(comptime self: *const ArgType) type {
        return switch (self.*) {
            .Bool => bool,
            .Uint => usize,
            .RangedInt, .Int => i64,
            .Float => f64,
            .String => []const u8,
            .Char => u8,
            .List => |inner| []const inner.GetType(),
            .Optional => |inner| ?inner.GetType(),
            .Enum => |T| T,
        };
    }

    pub fn GetInnerType(comptime self: *const ArgType) ?type {
        return switch (self.*) {
            .List => |inner| inner.GetType(),
            .Optional => |inner| inner.GetType(),
            else => null,
        };
    }

    pub fn defaultValue(comptime self: *const ArgType) self.GetType() {
        return switch (self.*) {
            .Bool => false,
            .Uint => 0,
            .RangedInt => |confine| confine.min,
            .Int => 0,
            .Float => 0.0,
            .String => "",
            .Char => 0,
            .List => &.{},
            .Optional => null,
            .Enum => |T| @as(T, @enumFromInt(0)),
        };
    }

    pub fn parseToValue(self: *const ArgType, value: []const u8, config: ParserConfig, allocator: std.mem.Allocator) !ArgValue {
        switch (self.*) {
            .Uint => {
                const int_value = std.fmt.parseInt(usize, value, 0) catch return InternalCliError.InvalidValue;
                return .{ .Uint = int_value };
            },
            .Int => return .{ .Int = std.fmt.parseInt(isize, value, 0) catch return InternalCliError.InvalidValue },
            .RangedInt => |constraint| {
                const int_value = std.fmt.parseInt(isize, value, 0) catch return InternalCliError.InvalidValue;
                if (int_value > constraint.max or int_value < constraint.min)
                    return InternalCliError.InvalidValue;

                return .{ .RangedInt = int_value };
            },
            // TODO: Better bool parsing
            .Bool => {
                const lowered = try std.ascii.allocLowerString(allocator, value);
                defer allocator.free(lowered);

                const bool_value = std.mem.eql(u8, lowered, "true") or
                    std.mem.eql(u8, lowered, "yes") or
                    std.mem.eql(u8, lowered, "y") or
                    std.mem.eql(u8, lowered, "1");

                return .{ .Bool = bool_value };
            },
            .Float => {
                const float_value = std.fmt.parseFloat(f64, value) catch return InternalCliError.InvalidValue;
                return .{ .Float = float_value };
            },
            .String => {
                return .{ .String = .{ .allocator = allocator, .value = try allocator.dupe(u8, value) } };
            },
            .Char => {
                if (value.len != 1)
                    return InternalCliError.InvalidValue;

                return .{ .Char = value[0] };
            },
            .Optional => |inner| {
                const val = try allocator.create(ArgValue);
                val.* = try inner.parseToValue(value, config, allocator);
                return .{ .Optional = .{ .allocator = allocator, .value = val } };
            },
            .List => |inner| {
                var list = std.ArrayList(ArgValue).init(allocator);
                defer list.deinit();

                var buf = std.ArrayList(u8).init(allocator);
                defer buf.deinit();

                var in_quotes = false;
                var is_escaped = false;

                for (value) |ch| {
                    if (ch == config.item_seperator and buf.items.len != 0 and !in_quotes and !is_escaped) {
                        try list.append(try inner.parseToValue(buf.items, config, allocator));
                        std.debug.print("Parsed str: {s}\n", .{buf.items});
                        buf.clearRetainingCapacity();
                        continue;
                    }

                    if (ch == '\\' and !is_escaped) {
                        is_escaped = true;
                        continue;
                    } else {
                        is_escaped = false;
                    }

                    if (ch == '"' or ch == '\'') {
                        in_quotes = !in_quotes;
                        continue;
                    }

                    try buf.append(ch);
                }

                try list.append(try inner.parseToValue(buf.items, config, allocator));

                if (in_quotes)
                    return InternalCliError.UnclosedDelimiter;

                return .{ .List = .{ .allocator = allocator, .value = try allocator.dupe(ArgValue, list.items) } };
            },
            .Enum => |T| {
                if (@typeInfo(T) != .Enum) {
                    return InternalCliError.InvalidValue;
                }
                if (config.allow_index_as_enum) {
                    const index_result: ?usize = std.fmt.parseInt(usize, value, 0) catch null;
                    if (index_result) |index| {
                        if (index < @typeInfo(T).Enum.fields.len) {
                            return .{ .Enum = index };
                        } else {
                            return InternalCliError.InvalidValue;
                        }
                    }
                }

                const enum_fields = @typeInfo(T).Enum.fields;

                inline for (0.., enum_fields) |i, field| {
                    const lower_field_name = try std.ascii.allocLowerString(allocator, field.name);
                    defer allocator.free(lower_field_name);
                    const lower_value = try std.ascii.allocLowerString(allocator, value);
                    defer allocator.free(lower_value);

                    if (std.mem.eql(u8, lower_field_name, lower_value)) {
                        return .{ .Enum = i };
                    }
                }

                return InternalCliError.InvalidValue;
            },
        }
    }
};

pub const ArgValue = union(enum) {
    Bool: bool,
    Uint: usize,
    Int: isize,
    RangedInt: isize,
    Float: f64,
    String: struct { allocator: std.mem.Allocator, value: []const u8 },
    Char: u8,
    List: struct { allocator: std.mem.Allocator, value: []ArgValue },
    Optional: ?struct { allocator: std.mem.Allocator, value: *ArgValue },
    Enum: usize,

    pub fn ofType(self: @This(), arg_type: ArgType) bool {
        return switch (arg_type) {
            .Bool => self == .Bool,
            .Uint => self == .Uint,
            .Int => self == .Int,
            .RangedInt => |constraint| self == .RangedInt and
                self.RangedInt <= constraint.max and
                self.RangedInt >= constraint.min,
            .Float => self == .Float,
            .String => self == .String,
            .Char => self == .Char,
            .List => self == .List,
            .Optional => self == .Optional,
            .Enum => self == .Enum,
        };
    }

    pub fn toArgType(self: @This()) ArgType {
        return switch (self) {
            .Bool => .Bool,
            .Uint => .Uint,
            .Int => .Int,
            .RangedInt => .RangedInt,
            .Float => .Float,
            .String => .String,
            .Char => .Char,
            .List => .List,
            .Optional => .Optional,
            .Enum => .Enum,
        };
    }

    pub fn deinit(self: *@This()) void {
        switch (self.*) {
            .String => |str| {
                str.allocator.free(str.value);
            },
            .List => |list| {
                // deinit the sub elements
                for (list.value) |*arg_val| {
                    arg_val.deinit();
                }
                // deinit the slice
                list.allocator.free(list.value);
            },
            .Optional => |inner| {
                // deinit sub elements
                if (inner) |inner_val| {
                    inner_val.value.deinit();
                    // deinit the pointer
                    // inner_val.allocator.free(inner_val);
                }
            },
            else => {},
        }

        // self.* = undefined;
    }
};

const ParserConfig = struct {
    /// The char between the argument, and its value, e.g. ' ' for '--hello world', or '=' for '--hello=world'
    value_sep: u8 = ' ',
    /// The prefix for a short argument, e.g. '-' for '-h', or '/' for '/h'
    short_arg_prefix: []const u8 = "-",
    /// The prefix for a long argument, e.g. '--' for '--help' or '//' for '//help'
    long_arg_prefix: []const u8 = "--",
    /// The seperator between a lists items, e.g. `" "` for `a b` or `,` for `a,b`
    item_seperator: u8 = ' ',
    /// If user is allowed to input the index of an enum value, instead of the enum values name.
    allow_index_as_enum: bool = true,
};

const ArgDef = struct {
    /// The string printed in the help page
    help: []const u8,
    /// The name of the argument. Only used for the generated struct field name, or the subcommands name.
    name: [:0]const u8,
    /// The name of the short argument, like 'h' for '-h'
    short: ?u8 = null,
    /// The name of the long argument, like 'help' for '--help'
    long: ?[]const u8 = null,
    /// If this argument is a positional argument. There can only be one positional
    /// argument per subcommand
    positional: bool = false,
    /// The type of the value
    // type: type = bool,
    type: ArgType = .Bool,
    /// The fields default value.
    default_value: ?ArgValue = null,
};

/// The type of argument being parsed, e.g. `.short` for `-h`, `.long` for `--help`, and `.value` for `help`
const ArgumentKind = enum {
    short,
    long,
    value,
};

pub fn Args(comptime arg_defs: ArgDefs) type {
    var fields: [arg_defs.len]std.builtin.Type.StructField = undefined;

    comptime for (0.., arg_defs) |i, arg| {
        // var field_name = try comptime g.allocator.dupe(u8, arg.name);
        // std.mem.replaceScalar(u8, &field_name, " ", "_");
        const field_name = arg.name;

        const FieldType = arg.type.GetType();

        // Comptime check to make sure user defined default value is
        // of same type as the arg
        if (arg.default_value) |def_val| {
            if (!def_val.ofType(arg.type)) {
                @compileError("Default value of \"" ++ field_name ++ "\" is not of type " ++ FieldType);
            }
        }

        fields[i] = .{
            .name = field_name,
            .type = FieldType,
            .default_value = @as(*const anyopaque, @ptrCast(&arg.type.defaultValue())),
            .is_comptime = false,
            .alignment = @alignOf(FieldType),
        };
    };

    const ArgStruct =
        @Type(.{
        .Struct = .{
            .layout = .auto,
            .fields = &fields,
            .decls = &.{},
            .is_tuple = false,
        },
    });
    return struct {
        const Self = @This();

        allocator: std.mem.Allocator,
        conf: ParserConfig,
        args: ArgStruct,

        pub fn print(self: Self) void {
            inline for (arg_defs) |arg_def| {
                if (arg_def.type.GetType() == []const u8) {
                    std.debug.print("{s}: {s}\n", .{ arg_def.name, @field(self.args, arg_def.name) });
                } else {
                    std.debug.print("{s}: {any}\n", .{ arg_def.name, @field(self.args, arg_def.name) });
                }
            }
        }

        pub fn deinit(self: *Self) void {
            const arg_fields = @typeInfo(@TypeOf(self.args)).Struct.fields;
            inline for (arg_fields) |arg| {
                const t_info = @typeInfo(arg.type);
                switch (t_info) {
                    .Pointer => {
                        self.allocator.free(@field(self.args, arg.name));
                    },
                    else => {},
                }
            }
        }

        pub fn parseArgs(allocator: std.mem.Allocator, config: ParserConfig) CliErr!Self {
            var args: [][]const u8 = allocator.alloc([]const u8, std.os.argv.len - 1) catch @panic("Ran out of memory");
            defer allocator.free(args);

            // Turn the std.os.argv from a `[][*:0]const u8` to a `[][]const u8`
            for (0..std.os.argv.len - 1) |i| {
                args[i] = std.mem.span(std.os.argv[i + 1]);
            }

            return Self.parseArgsFromArgv(args, allocator, config);
        }

        pub fn parseArgsFromArgv(argv: []const []const u8, allocator: std.mem.Allocator, config: ParserConfig) CliErr!Self {
            var data = Args(arg_defs){
                .allocator = allocator,
                .conf = config,
                .args = .{},
            };

            var arg_state: ArgState(arg_defs) = .{};

            inline for (arg_defs) |arg_def| {
                if (arg_def.default_value) |def_val| {
                    setField(arg_defs, &data, arg_def.name, def_val) catch return CliErr.BadArg;
                    @field(arg_state, arg_def.name) = true;
                }
            }

            // If the short argument prefix is the same as the long prefix, so `-o` and `-output` are both valid.
            // If this value is true, you cannot chain short arguments together, so `-al` is not the same as `-a -l`
            const short_eql_long = std.mem.eql(u8, config.short_arg_prefix, config.long_arg_prefix);
            _ = short_eql_long;

            const arg_str = std.mem.join(allocator, " ", argv) catch @panic("Ran out of memory");
            defer allocator.free(arg_str);

            var buffer = std.ArrayList(u8).init(allocator);
            defer buffer.deinit();

            var i: usize = 0;
            while (i < arg_str.len) {
                buffer.append(arg_str[i]) catch @panic("Ran out of memory");

                if (!isValidArgChar(arg_str[i])) {
                    i += 1;
                    continue;
                }

                const curr_arg_type: ArgumentKind = blk: {
                    if (std.mem.startsWith(u8, buffer.items, config.long_arg_prefix)) {
                        break :blk .long;
                    } else if (std.mem.startsWith(u8, buffer.items, config.short_arg_prefix)) {
                        break :blk .short;
                    } else {
                        break :blk .value;
                    }
                };

                if (curr_arg_type == .short) {
                    while (i < arg_str.len and arg_str[i] != ' ') {
                        if (matchArg(arg_defs, &.{arg_str[i]}, .short)) |arg_def| {
                            setField(arg_defs, data, arg_def.name, .{ .Bool = true });
                        }
                        i += 1;
                    }
                }

                std.debug.print("Curr Char: {s}\nCurr Type: {}\n\n", .{ [1]u8{arg_str[i]}, curr_arg_type });
                i += 1;
            }

            // for (argv) |arg| {
            //     const slice_arg = std.mem.span(arg);
            //     const curr_arg_type: ArgumentType = blk: {
            //         if (std.mem.startsWith(u8, slice_arg, config.short_arg_prefix)) {
            //             break :blk .short;
            //         } else if (std.mem.startsWith(u8, slice_arg, config.long_arg_prefix)) {
            //             break :blk .long;
            //         } else {
            //             break :blk .value;
            //         }
            //     };
            //
            //     _ = curr_arg_type;
            // }

            inline for (arg_defs) |arg_def| {
                if (!@field(arg_state, arg_def.name))
                    return CliErr.MissingArgs;
            }

            return data;
        }
    };
}

fn ArgState(comptime arg_defs: ArgDefs) type {
    var fields: [arg_defs.len]std.builtin.Type.StructField = undefined;

    comptime for (0.., arg_defs) |i, arg| {
        const field_name = arg.name;

        const default =
            (arg.type == .Optional or arg.default_value != null);

        fields[i] = .{
            .name = field_name,
            .type = bool,
            .default_value = &default,
            .is_comptime = false,
            .alignment = @alignOf(bool),
        };
    };

    return @Type(.{
        .Struct = .{
            .layout = .auto,
            .fields = &fields,
            .decls = &.{},
            .is_tuple = false,
        },
    });
}

const CliErr = error{
    BadArg,
    MissingArgs,
};

const InternalCliError = error{
    InvalidFieldName,
    InvalidValue,
    UnclosedDelimiter,
};

pub fn setField(
    comptime arg_defs: ArgDefs,
    data: *Args(arg_defs),
    field_name: []const u8,
    value: ArgValue,
) InternalCliError!void {
    if (!hasField(arg_defs, field_name))
        return InternalCliError.InvalidFieldName;

    inline for (arg_defs) |arg_def| {
        if (std.mem.eql(u8, arg_def.name, field_name)) {
            const field_ptr = &@field(data.args, arg_def.name);
            const field_t = @TypeOf(field_ptr.*);

            // TODO: Better error handling
            @field(data.args, arg_def.name) = setFieldInner(field_t, arg_def, data.allocator, value) catch @panic("Got some error");
        }
    }
}

fn setFieldInner(
    T: type,
    comptime arg: ArgDef,
    allocator: std.mem.Allocator,
    value: ArgValue,
) !T {
    switch (value) {
        .Bool => |b| {
            if (T == bool)
                return b;
        },
        .Int => |i| {
            if (T == isize)
                return i;
        },
        .Uint => |u| {
            if (T == usize)
                return u;
        },
        .RangedInt => |ri| {
            if (T == isize)
                return ri;
        },
        .Float => |f| {
            if (T == f64)
                return f;
        },
        .String => |s| {
            if (T == []const u8)
                return try allocator.dupe(u8, s.value);
        },
        .Char => |ch| {
            if (T == u8)
                return ch;
        },
        .List => |list| {
            if (arg.type.GetInnerType()) |inner_t| {
                var tmp_list = try std.ArrayList(inner_t).initCapacity(allocator, list.value.len);
                defer tmp_list.deinit();

                for (list.value) |val| {
                    try tmp_list.append(try setFieldInner(inner_t, arg, allocator, val));
                }

                if (T == []const inner_t) {
                    return try allocator.dupe(inner_t, tmp_list.items);
                }
            }
        },
        .Optional => |opt| {
            _ = opt;
            @panic("Optionals not implemented");
        },
        .Enum => |idx| {
            if (@typeInfo(T) == .Enum)
                return @as(T, @enumFromInt(idx));
        },
    }

    // TODO: Better error msg
    const err_msg = try std.fmt.allocPrint(allocator, "Value of {} is of type {}, which it shoulnd't be", .{ value, T });
    defer allocator.free(err_msg);
    @panic(err_msg);
}

fn matchArg(comptime arg_defs: ArgDefs, name: []const u8, kind: ArgumentKind) ?ArgDef {
    inline for (arg_defs) |arg_def| {
        switch (kind) {
            .short => {
                if (std.mem.eql(u8, arg_def.short, name))
                    return arg_def;
            },
            .long => {
                if (std.mem.eql(u8, arg_def.long, name))
                    return arg_def;
            },
            .value => break,
        }
    }

    return null;
}

pub fn hasField(comptime arg_defs: ArgDefs, field_name: []const u8) bool {
    inline for (arg_defs) |arg_def| {
        if (std.mem.eql(u8, arg_def.name, field_name))
            return true;
    }

    return false;
}

fn isValidArgChar(ch: u8) bool {
    return std.ascii.isAlphanumeric(ch) or ch == '_';
}
