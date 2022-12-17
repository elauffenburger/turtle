const std = @import("std");
const mem = std.mem;

pub const Args = struct {
    const Self = @This();

    cmd_str: ?[]u8 = null,

    pub fn parse(allocator: *mem.Allocator) !Self {
        var args: Self = .{};

        var args_iter = std.process.args();
        while (args_iter.next()) |arg| {
            if (mem.eql(u8, arg, "-c")) {
                if (args_iter.next()) |next| {
                    args.cmd_str.? = try allocator.dupe(u8, next);
                } else {
                    unreachable;
                }
            }
        }

        return args;
    }
};