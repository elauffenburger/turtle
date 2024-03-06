const std = @import("std");
const cmd = @import("cmd.zig");

pub const CmdExecutor = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    vars: std.AutoHashMap([]u8, []u8),
    stdin_fno: u32,
    stdout_fn: u32,
    pg_id: u32,
    last_pid: u32,

    pub fn init(allocator: std.mem.Allocator) Self {
        .{
            .allocator = allocator,
            .vars = std.AutoHashMap([]u8, []u8).init(allocator),
            .stdin_fno = std.c.STDIN_FILENO,
            .stdout_fn = std.c.STDOUT_FILENO,
            .pg_id = 0,
            .last_pid = 0,
        };
    }

    pub fn exec(self: *Self, command: *cmd.Cmd) !u8 {}
};
