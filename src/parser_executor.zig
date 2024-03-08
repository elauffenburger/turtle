const std = @import("std");
const mem = std.mem;

const cmd_parser = @import("cmd_parser.zig");
const cmd_executor = @import("cmd_executor.zig");

pub const ParserExecutor = struct {
    allocator: mem.Allocator,

    pub fn init(allocator: mem.Allocator) ParserExecutor {
        return .{ .allocator = allocator };
    }

    pub fn exec(self: ParserExecutor, line: []u8) !u8 {
        var parser = cmd_parser.CmdParser.init(self.allocator, line);

        var lastStatus: u8 = 0;
        while (true) {
            const cmd = parser.parse() catch |err| switch (err) {
                cmd_parser.Error.EOF => break,
                else => return err,
            };

            var executor = cmd_executor.CmdExecutor.init(self.allocator);
            lastStatus = try executor.exec(cmd);
        }

        return lastStatus;
    }
};
