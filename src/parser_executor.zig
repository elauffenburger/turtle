const std = @import("std");
const mem = std.mem;

const cmd_parser = @import("parser/cmd_parser.zig");
const cmd_executor = @import("executor/cmd_executor.zig");

pub const ParserExecutor = struct {
    allocator: mem.Allocator,
    executor: cmd_executor.CmdExecutor,

    pub const Options = struct {
        pub const OutputType = enum {
            command,
        };

        output: ?OutputType,
    };

    pub fn init(allocator: mem.Allocator) ParserExecutor {
        return .{
            .allocator = allocator,
            .executor = cmd_executor.CmdExecutor.init(allocator),
        };
    }

    pub fn exec(self: *ParserExecutor, line: []u8, options: Options) !u8 {
        var parser = cmd_parser.CmdParser.init(self.allocator, line);

        const execOpts = cmd_executor.ExecOpts{
            .stdin_fno = std.posix.STDIN_FILENO,
            .stdout_fno = std.posix.STDOUT_FILENO,
            .wait = true,
        };

        var lastStatus: u8 = 0;
        while (true) {
            const command = parser.parse() catch |err| switch (err) {
                cmd_parser.ParseError.EOF => break,
                else => return err,
            };

            if (options.output == .command) {
                try std.json.stringify(command, .{ .whitespace = .indent_1 }, std.io.getStdOut().writer());
                return 0;
            }

            lastStatus = try self.executor.exec(command.*, execOpts);
        }

        return lastStatus;
    }
};
