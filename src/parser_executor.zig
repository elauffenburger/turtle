const std = @import("std");
const mem = std.mem;

const CmdParser = @import("cmd_parser.zig").CmdParser;
const CmdExecutor = @import("cmd_executor.zig").CmdExecutor;

pub const ParserExecutor = struct {
    allocator: mem.Allocator,

    pub fn init(allocator: mem.Allocator) ParserExecutor {
        return .{ .allocator = allocator };
    }

    pub fn exec(self: ParserExecutor, line: []u8) !u8 {
        while (true) {
            var parser = CmdParser.init(self.allocator, line);

            const cmd = try parser.parse();

            var executor = CmdExecutor.init(self.allocator);
            const status = try executor.exec(cmd);
            if (status != 0) {
                return @intCast(if (status > 255) 255 else status);
            }
        }

        return 0;
    }
};
