const std = @import("std");
const debug = std.debug;
const mem = std.mem;
const os = std.os;

const Args = @import("args.zig").Args;
const ParserExecutor = @import("parser_executor.zig").ParserExecutor;

const c = @cImport({
    @cInclude("stdio.h");

    @cInclude("readline/history.h");
    @cInclude("readline/readline.h");
});

pub fn main() void {
    emain() catch {
        os.exit(1);
    };
}

fn emain() !void {
    var allocator = std.heap.page_allocator;
    var parser_executor = try ParserExecutor.init(&allocator);

    const args = try Args.parse(&allocator);

    if (args.filename) |filename| {
        var file_line_iter = std.mem.split(u8, try std.fs.cwd().readFileAlloc(allocator, filename, 1000000000000), "\n");
        while (file_line_iter.next()) |line| {
            var line_copy = try allocator.alloc(u8, line.len);
            mem.copy(u8, line_copy, line);

            const status = try parser_executor.parse_exec(line_copy);
            if (status != 0) {
                std.os.exit(status);
            }
        }

        return;
    }

    if (args.cmd_str) |cmd_str| {
        const status = try parser_executor.parse_exec(cmd_str);
        if (status != 0) {
            std.os.exit(status);
        }

        return;
    }

    try interactive(parser_executor);
}

fn interactive(parser_executor: *ParserExecutor) !void {
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
                _ = c.add_history(line.?);
            }
        }

        const status = try parser_executor.parse_exec(mem.span(line.?));
        if (status != 0) {
            std.os.exit(status);
        }
    }
}
