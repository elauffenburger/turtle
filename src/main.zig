const std = @import("std");
const mem = std.mem;

const Args = @import("args.zig").Args;
const ParserExecutor = @import("parser_executor.zig").ParserExecutor;

const c = @cImport({
    @cInclude("stdio.h");
    @cInclude("signal.h");

    @cInclude("readline/history.h");
    @cInclude("readline/readline.h");
});

pub fn main() void {
    emain() catch {
        std.posix.exit(1);
    };
}

fn emain() !void {
    var allocator = std.heap.page_allocator;
    var parser_executor = ParserExecutor.init(allocator);

    const args = try Args.parse(allocator);

    const parser_executor_options = ParserExecutor.Options{
        .output = args.output,
    };

    if (args.filename) |filename| {
        var file_line_iter = std.mem.split(u8, try std.fs.cwd().readFileAlloc(allocator, filename, 1000000000000), "\n");
        while (file_line_iter.next()) |line| {
            const line_copy = try allocator.alloc(u8, line.len);
            @memcpy(line_copy, line);

            const status = try parser_executor.exec(line_copy, parser_executor_options);
            if (status != 0) {
                std.posix.exit(status);
            }
        }

        return;
    }

    if (args.cmd_str) |cmd_str| {
        const status = try parser_executor.exec(cmd_str, parser_executor_options);
        std.posix.exit(status);
    }

    try interactive(allocator, &parser_executor, parser_executor_options);
}

fn interactive(allocator: std.mem.Allocator, parser_executor: *ParserExecutor, options: ParserExecutor.Options) !void {
    while (true) {
        const line_ptr = c.readline("🐢> ");
        const line = mem.span(line_ptr);

        if (!mem.eql(u8, line, "")) {
            _ = c.add_history(line_ptr);
        }

        _ = parser_executor.exec(line, options) catch {
            const buf = std.fmt.allocPrint(allocator, "critical error executing command:\n===\n{s}===\n", .{line}) catch std.posix.exit(1);
            defer allocator.free(buf);

            try std.io.getStdErr().writeAll(buf);
            continue;
        };

        std.c.free(line_ptr);
    }
}
