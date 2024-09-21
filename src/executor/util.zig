const std = @import("std");

pub const c = @cImport({
    @cInclude("fcntl.h");
    @cInclude("setjmp.h");
    @cInclude("signal.h");
    @cInclude("stdio.h");
    @cInclude("string.h");
    @cInclude("sys/stat.h");
    @cInclude("sys/wait.h");
    @cInclude("unistd.h");
});

pub fn giveup(comptime fmt: []const u8, args: anytype) void {
    std.log.err(fmt, args);
    std.posix.exit(1);
    unreachable;
}
