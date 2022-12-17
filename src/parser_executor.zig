const std = @import("std");
const mem = std.mem;

const c = @cImport({
    @cInclude("cmd.h");
    @cInclude("cmd_executor/cmd_executor.h");
    @cInclude("cmd_parser.h");
});

fn toCString(allocator: *mem.Allocator, str: []u8) !struct { allocd: ?[]u8, str: [*:0]u8 } {
    if (str.len > 0 and str[str.len - 1] == 0) {
        return .{ .allocd = null, .str = @ptrCast([*:0]u8, str.ptr) };
    }

    var buf = try allocator.allocSentinel(u8, str.len, 0);
    mem.copy(u8, buf[0..str.len], str);

    return .{ .allocd = buf, .str = buf.ptr };
}

pub const ParserExecutor = struct {
    allocator: *mem.Allocator,

    parser: *c.cmd_parser,
    executor: *c.cmd_executor,

    pub fn init(allocator: *mem.Allocator) !*ParserExecutor {
        var self = try allocator.create(ParserExecutor);
        self.allocator = allocator;
        self.parser = c.cmd_parser_new();
        self.executor = c.cmd_executor_new();

        return self;
    }

    pub fn parse_exec(self: *ParserExecutor, line: []u8) !u8 {
        const c_line = try toCString(self.allocator, line);
        if (c_line.allocd) |allocd| {
            // defer self.allocator.free(allocd);
            _ = allocd;
        }

        c.cmd_parser_set_next(self.parser, c_line.str);

        var cmd: ?*c.cmd = null;
        while (true) {
            cmd = c.cmd_parser_parse_next(self.parser);
            if (cmd == null) {
                break;
            }

            const status: c_int = c.cmd_executor_exec(self.executor, cmd);
            if (status != 0) {
                return @intCast(u8, if (status > 255) 255 else status);
            }

            c.cmd_free(cmd);
        }

        return 0;
    }
};
