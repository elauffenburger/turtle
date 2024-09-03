const std = @import("std");
const mem = std.mem;

const cmd_parser = @import("cmd_parser.zig");
const cmd_executor = @import("cmd_executor.zig");

pub const ParserExecutor = struct {
    allocator: mem.Allocator,
    executor: cmd_executor.CmdExecutor,

    pub fn init(allocator: mem.Allocator) ParserExecutor {
        return .{
            .allocator = allocator,
            .executor = cmd_executor.CmdExecutor.init(allocator),
        };
    }

    pub fn exec(self: *ParserExecutor, line: []u8) !u8 {
        var parser = cmd_parser.CmdParser.init(self.allocator, line);

        const execOpts = cmd_executor.CmdExecutor.ExecOpts{
            .stdin_fno = std.posix.STDIN_FILENO,
            .stdout_fno = std.posix.STDOUT_FILENO,
            .wait = true,
        };

        var lastStatus: u8 = 0;
        while (true) {
            const cmd = parser.parse() catch |err| switch (err) {
                cmd_parser.Error.EOF => break,
                else => return err,
            };

            lastStatus = try self.executor.exec(cmd, execOpts);
        }

        return lastStatus;
    }
};
