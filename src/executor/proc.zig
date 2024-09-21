const std = @import("std");

const util = @import("util.zig");
const c = util.c;

pub const ForkExecArgs = struct {
    argv: [][]u8,
    envp: [][]u8,
    stdin_fno: c_int,
    stdout_fno: c_int,
};

pub fn forkExecNoWait(allocator: std.mem.Allocator, args: ForkExecArgs) !i32 {
    const pid = try std.posix.fork();
    if (pid == 0) {
        if (args.stdin_fno != c.STDIN_FILENO) {
            replaceFd(args.stdin_fno, std.posix.STDIN_FILENO);
        }

        if (args.stdout_fno != c.STDOUT_FILENO) {
            replaceFd(args.stdout_fno, std.posix.STDOUT_FILENO);
        }

        const argv = try toCStringVec(allocator, args.argv);
        // defer self.allocator.destroy(argv.ptr);

        const envp = try toCStringVec(allocator, args.envp);
        // defer self.allocator.destroy(envp);

        // Finally run this thing.
        const err = std.posix.execvpeZ(argv[0].?, argv, envp);

        // If we got here, that means the exec failed!
        util.giveup("execTerm: exec {s} failed: {any}", .{ args.argv[0], err });
    }

    return pid;
}

pub fn forkExec(allocator: std.mem.Allocator, args: ForkExecArgs) !u8 {
    return wait(try forkExecNoWait(allocator, args));
}

pub fn wait(pid: i32) u8 {
    // Wait for the child to finish.
    const res = std.posix.waitpid(pid, 0);

    // HACK: looks like there's some kind of result code mangling on Mac OS at least
    // that shifts the num 8 bits to the right, so let's undo that...
    const status: u8 = @intCast(res.status >> 8);

    return status;
}

fn toCStringVec(allocator: std.mem.Allocator, slice: [][]u8) ![*:null]?[*:0]const u8 {
    const vec = try allocator.allocSentinel(?[*:0]const u8, slice.len, null);
    for (slice, 0..) |str, i| {
        vec[i] = try allocator.dupeZ(u8, str);
    }

    return vec;
}

fn replaceFd(old: c_int, new: c_int) void {
    _ = c.dup2(old, new);
    _ = c.close(old);
}

fn sigIgnore(_: c_int) callconv(.C) void {}

pub fn waitForDebugger() void {
    _ = c.signal(1, sigIgnore);
    _ = c.sleep(10);
}
