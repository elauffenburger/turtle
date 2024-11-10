const std = @import("std");
const mem = std.mem;

const ComptimeStringMap = @import("./collections/comptime_string_map.zig").ComptimeStringMap;
const ParserExecutor = @import("parser_executor.zig").ParserExecutor;

pub const Args = struct {
    const Self = @This();

    const OutputTypeLookup = ComptimeStringMap(ParserExecutor.Options.OutputType, .{
        .cmd = .command,
        .command = .command,
        .exec = .executableCommand,
        .execmd = .executableCommand,
        .execommand = .executableCommand,
        .executablecommand = .executableCommand,
    });

    cmd_str: ?[]u8 = null,
    filename: ?[]u8 = null,
    output: ?ParserExecutor.Options.OutputType = null,

    pub fn parse(allocator: mem.Allocator) !Self {
        var args: Self = .{};

        var args_iter = std.process.args();
        _ = args_iter.next();

        while (args_iter.next()) |arg| {
            if (mem.eql(u8, arg, "-c")) {
                if (args_iter.next()) |next| {
                    args.cmd_str = try allocator.dupe(u8, next);
                    continue;
                } else {
                    std.log.err("command string required if -c provided", .{});
                    std.posix.exit(1);
                }
            }

            if (mem.eql(u8, arg, "-o")) {
                if (args_iter.next()) |next| {
                    const output = next;
                    const output_normalized = std.ascii.lowerString(try allocator.alloc(u8, output.len), output);

                    if (OutputTypeLookup.get(output_normalized)) |output_type| {
                        args.output = output_type;
                        continue;
                    }

                    try std.io.getStdErr().writeAll(try std.fmt.allocPrint(allocator, "unknown output format: \"{s}\"", .{output}));
                    continue;
                } else {
                    std.log.err("output type required if -o provided", .{});
                    std.posix.exit(1);
                }
            }

            if (args.filename) |filename| {
                std.log.err("cannot provided multiple filenames: '{s}', '{s}'", .{ filename, arg });
                std.posix.exit(1);
            } else {
                args.filename = try allocator.dupe(u8, arg);
            }
        }

        if (args.filename != null and args.cmd_str != null) {
            std.log.err("cannot provided file and command string", .{});
            std.posix.exit(1);
        }

        return args;
    }
};
