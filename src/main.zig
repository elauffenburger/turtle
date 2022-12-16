const std = @import("std");
const mem = std.mem;

const c = @cImport({
    @cInclude("cmd.h");
    @cInclude("cmd_executor/cmd_executor.h");
    @cInclude("cmd_parser.h");

    @cInclude("stdio.h");

    @cInclude("readline/history.h");
    @cInclude("readline/readline.h");
});

pub fn main() void {
    var parser = c.cmd_parser_new();
    var executor = c.cmd_executor_new();

    var line: ?[*:0]u8 = null;
    while (true) {
        if (line != null) {
            std.c.free(line);
            line = null;
        }

        line = c.readline("🐢> ");
        {
            const line_slice = mem.span(line.?);
            if (!mem.eql(u8, line_slice, "")) {
                c.add_history(line.?);
            }
        }

        c.cmd_parser_set_next(parser, line);

        var cmd: ?*c.cmd = null;
        while (true) {
            cmd = c.cmd_parser_parse_next(parser);
            if (cmd == null) {
                break;
            }

            const status = c.cmd_executor_exec(executor, cmd);
            if (status != 0) {
                std.os.exit(@intCast(u8, status));
            }

            c.cmd_free(cmd);
        }
    }
}
