const std = @import("std");
const cmd = @import("cmd.zig");

const c = @cImport({
    @cInclude("fcntl.h");
    @cInclude("setjmp.h");
    @cInclude("stdio.h");
    @cInclude("string.h");
    @cInclude("sys/stat.h");
    @cInclude("sys/wait.h");
    @cInclude("unistd.h");
});

const Error = error{
    CmdExit,
};

pub const CmdExecutor = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    vars: std.StringHashMap([]u8),
    stdin_fno: c_int,
    stdout_fno: c_int,
    last_pid: ?c_int,

    exit_status_code: ?u8,

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .vars = std.StringHashMap([]u8).init(allocator),
            .stdin_fno = c.STDIN_FILENO,
            .stdout_fno = c.STDOUT_FILENO,
            .last_pid = null,
            .exit_status_code = null,
        };
    }

    pub fn forkExec(self: *Self, args: [][]u8) !u8 {
        var pid = try std.os.fork();
        if (pid == 0) {
            if (self.stdin_fno != c.STDIN_FILENO) {
                _ = c.close(c.STDIN_FILENO);
                _ = c.dup(self.stdin_fno);
            }

            if (self.stdout_fno != c.STDOUT_FILENO) {
                _ = c.close(c.STDOUT_FILENO);
                _ = c.dup(self.stdout_fno);
            }

            const argv = try CStringVecHandle.fromSlice(self.allocator, args);
            // defer argv.deinit();

            const env_pairs = blk: {
                var res = std.ArrayList([]u8).init(self.allocator);

                var iter = self.vars.iterator();
                var maybe_entry = iter.next();
                while (maybe_entry != null) {
                    const entry = maybe_entry.?;

                    try res.append(try std.fmt.allocPrint(self.allocator, "{s}={s}", .{ entry.key_ptr.*, entry.value_ptr.* }));
                }

                break :blk try res.toOwnedSlice();
            };
            // defer self.allocator.free(env_pairs);

            const envp = try CStringVecHandle.fromSlice(self.allocator, env_pairs);
            // defer envp.deinit();

            // Finally run this thing.
            const err = std.os.execvpeZ(argv.vec[0].?, argv.vec.ptr, envp.vec.ptr);

            // If we got here, that means the exec failed!
            self.giveup("execTerm: exec {s} failed: {any}", .{ args[0], err });
        }

        // Record the child process' pid as the last_pid.
        self.last_pid = pid;

        // Wait for the child to finish.
        const res = std.os.waitpid(pid, 0);

        // HACK: looks like there's some kind of result code mangling on Mac OS at least
        // that shifts the num 8 bits to the right, so let's undo that...
        const status: u8 = @intCast(res.status >> 8);

        return status;
    }

    pub fn exec(self: *Self, command: *cmd.Cmd) anyerror!u8 {
        var args = std.ArrayList([]u8).init(self.allocator);

        // Set up executor err jump.
        for (command.parts.items, 0..) |part, i| {
            switch (part) {
                .varAssign => |varAssign| {
                    const name = varAssign.name;
                    const value = try self.wordToStr(varAssign.value);

                    // If this is the only part of the command, set the var as an executor
                    // var.
                    if (i == command.parts.items.len - 1) {
                        try self.vars.put(name, value);
                    }
                    // Otherwise, set it as a var for the environment for the command.
                    else {
                        try command.env_vars.put(name, value);
                    }
                },

                .word => |word| {
                    try args.append(try self.wordToStr(word));
                },

                .pipedCmd => |pipedCmd| {
                    const original_fnos = [_]c_int{ self.stdin_fno, self.stdout_fno };

                    var pipe_fnos = [2]c_int{ 0, 0 };
                    if (c.pipe(pipe_fnos[0..].ptr) < 0) {
                        self.giveup("exec: pipe failed", .{});
                    }

                    // Write to the write end of the pipe.
                    self.stdout_fno = pipe_fnos[1];

                    // Execute the left side.
                    const left_status = try self.forkExec(args.items);
                    if (left_status != 0) {
                        _ = c.close(pipe_fnos[0]);
                        _ = c.close(pipe_fnos[1]);

                        self.stdin_fno = original_fnos[0];
                        self.stdout_fno = original_fnos[1];

                        return left_status;
                    }

                    // Close the write end of the pipe (we're done writing), restore the output fno, and read from the read end.
                    _ = c.close(pipe_fnos[1]);
                    self.stdout_fno = original_fnos[1];
                    self.stdin_fno = pipe_fnos[0];

                    // Execute the right side.
                    const right_status = try self.exec(pipedCmd);

                    // Restore the read fno.
                    self.stdin_fno = original_fnos[0];

                    return right_status;
                },

                .orCmd => |orCmd| {
                    const left_status = try self.forkExec(args.items);

                    // If the left side succeeded, we're done!
                    if (left_status == 0) {
                        return 0;
                    }

                    // Otherwise, execute the or'd command.
                    return try self.exec(orCmd);
                },

                .andCmd => |andCmd| {
                    const left_status = try self.forkExec(args.items);

                    // If the left side failed, bail!
                    if (left_status == 0) {
                        return left_status;
                    }

                    // Otherwise, execute the and'd command.
                    return try self.exec(andCmd);
                },
            }
        }

        if (args.items.len == 0) {
            return 0;
        }

        return try self.forkExec(args.items);
    }

    fn wordToStr(self: *Self, word: *cmd.CmdWord) anyerror![]u8 {
        var res = std.ArrayList(u8).init(self.allocator);

        for (word.parts.items) |part| {
            switch (part.*) {
                .literal => |literal| {
                    try res.appendSlice(literal);
                },
                .str => |str| {
                    if (str.quoted) {
                        for (str.parts.items) |str_part| {
                            switch (str_part.*) {
                                .literal => |literal| {
                                    try res.appendSlice(literal);
                                },

                                .variable => |variable| {
                                    const val = try self.getVar(variable.name);
                                    if (val != null) {
                                        try res.appendSlice(val.?);
                                    }
                                },
                            }
                        }
                    } else {
                        for (str.parts.items) |str_part| {
                            switch (str_part.*) {
                                .literal => |literal| {
                                    try res.appendSlice(literal);
                                },

                                .variable => |_| {
                                    @panic("not implemented");
                                },
                            }
                        }
                    }
                },

                .variable => |variable| {
                    const val = try self.getVar(variable.name);
                    if (val != null) {
                        try res.appendSlice(val.?);
                    }
                },

                .cmd_sub => |cmd_sub| {
                    const original_fnos = [_]c_int{ self.stdin_fno, self.stdout_fno };

                    var pipe_fnos = [2]c_int{ 0, 0 };
                    if (c.pipe(&pipe_fnos) < 0) {
                        self.giveup("wordToStr: pipe failed", .{});
                    }

                    // Write to the write end of the pipe while executing the cmd.
                    self.stdout_fno = pipe_fnos[1];
                    const status = try self.exec(cmd_sub);
                    self.stdout_fno = original_fnos[1];

                    // Signal that we're done writing.
                    _ = c.close(pipe_fnos[1]);

                    // If the command failed, bail!
                    if (status != 0) {
                        try self.exitErr(status);
                    }

                    // Read the result.
                    var arg = blk: {
                        var argRes = std.ArrayList(u8).init(self.allocator);

                        var buf = [_]u8{0} ** c.BUFSIZ;

                        var n: usize = @intCast(c.read(pipe_fnos[0], &buf, buf.len));
                        while (n != 0) {
                            var bufSlice: []u8 = buf[0..];

                            if (n < c.BUFSIZ) {
                                // Remove the trailing newline.
                                bufSlice = bufSlice[0..n];
                                bufSlice[n - 1] = 0;
                            }

                            try argRes.appendSlice(bufSlice);

                            n = @intCast(c.read(pipe_fnos[0], &buf, buf.len));
                        }

                        break :blk argRes;
                    };

                    // Close the read end.
                    _ = c.close(pipe_fnos[0]);

                    try res.appendSlice(try arg.toOwnedSlice());
                },

                .proc_sub => |proc_sub| {
                    const file_name_template = "/tmp/turtle-proc-XXXXXX\x00";
                    var file_name_buf: [file_name_template.len:0]u8 = undefined;
                    std.mem.copyForwards(u8, &file_name_buf, file_name_template);

                    var fd = c.mkstemp(file_name_buf[0..].ptr);
                    if (fd < 0) {
                        self.giveup("wordToStr: proc sub file creation failed", .{});
                    }

                    if (c.chmod(file_name_buf[0..].ptr, 0o777) < 0) {
                        self.giveup("wordToStr: proc sub file chmod failed", .{});
                    }

                    const original_out_fd = self.stdout_fno;

                    // Write to the file during execution.
                    self.stdout_fno = fd;
                    const maybeStatus = self.exec(proc_sub);
                    self.stdout_fno = original_out_fd;

                    // Signal that we're done writing to the file.
                    _ = c.close(fd);

                    // If the command failed, bail!
                    const status = try maybeStatus;
                    if (status != 0) {
                        try self.exitErr(status);
                    }

                    // Reopen the file with the correct flags.
                    fd = c.open(file_name_buf[0..].ptr, c.O_RDONLY);
                    if (fd < 0) {
                        self.giveup("wordToStr: proc sub file reopen failed", .{});
                        unreachable;
                    }

                    // Provide the filename as "/dev/fd/$FD".
                    try res.appendSlice(try std.fmt.allocPrint(self.allocator, "/dev/fd/{d}", .{fd}));
                },
            }
        }

        return res.toOwnedSlice();
    }

    fn getVar(self: Self, name: []u8) !?[]u8 {
        // Check if this is a special var name.
        if (std.mem.eql(u8, "!", name)) {
            return try std.fmt.allocPrint(self.allocator, "{d}", .{self.last_pid.?});
        }

        // CHeck if we have a var def for the command.
        var value = self.vars.get(name);
        if (value == null) {
            // Fall back to the environment.
            const envVal = std.os.getenv(name);
            if (envVal != null) {
                const buf = try self.allocator.alloc(u8, envVal.?.len - 1);
                @memcpy(buf, envVal.?[0 .. envVal.?.len - 1]);

                value = buf;
            }
        }

        return value;
    }

    fn giveup(_: Self, comptime fmt: []const u8, args: anytype) void {
        std.debug.print(fmt, args);
        std.os.exit(1);
    }

    fn exitErr(self: *Self, status: u32) Error!void {
        self.exit_status_code = @intCast(status);
    }

    const CStringVecHandle = struct {
        allocator: std.mem.Allocator,
        vec: [:null]?[*:0]const u8,
        vec_item_slices: [][]u8,

        pub fn fromSlice(allocator: std.mem.Allocator, slice: [][]u8) !@This() {
            const vec_item_slices = try allocator.alloc([]u8, slice.len);

            const res = try allocator.allocSentinel(?[*:0]const u8, slice.len, null);
            for (slice, 0..) |subSlice, i| {
                const cArg = try allocator.dupeZ(u8, subSlice);

                res[i] = cArg;
                vec_item_slices[i] = cArg;
            }

            return .{
                .allocator = allocator,
                .vec = res,
                .vec_item_slices = vec_item_slices,
            };
        }

        // pub fn deinit(self: @This()) void {
        //     for (self.vec) |arg| {
        //         self.allocator.free(arg);
        //     }

        //     self.allocator.free(self.vec);
        // }
    };
};
