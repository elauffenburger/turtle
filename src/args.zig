const std = @import("std");
const mem = std.mem;

pub const Args = struct {
    const Self = @This();

    const ParseArgsError = error{
        FilenameAlreadySpecified,
    };

    cmd_str: ?[]u8 = null,
    filename: ?[]u8 = null,

    pub fn parse(allocator: *mem.Allocator) !Self {
        var args: Self = .{};

        var args_iter = std.process.args();
        _ = args_iter.next();

        while (args_iter.next()) |arg| {
            if (mem.eql(u8, arg, "-c")) {
                if (args_iter.next()) |next| {
                    args.cmd_str = try allocator.dupe(u8, next);
                } else {
                    unreachable;
                }
            }

            if (args.filename) |_| {
                return ParseArgsError.FilenameAlreadySpecified;
            } else {
                args.filename = try allocator.dupe(u8, arg);
            }
        }

        return args;
    }
};
