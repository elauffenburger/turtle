const std = @import("std");
const cmd = @import("cmd.zig");

const c = @cImport({
    @cInclude("fcntl.h");
    @cInclude("setjmp.h");
    @cInclude("stdio.h");
    @cInclude("sys/stat.h");
    @cInclude("unistd.h");
});

pub const CmdExecutor = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    vars: std.AutoHashMap([]u8, []u8),
    stdin_fno: c_int,
    stdout_fno: c_int,
    last_pid: c_int,
    err_jump: c.jmp_buf,

    pub fn init(allocator: std.mem.Allocator) Self {
        .{
            .allocator = allocator,
            .vars = std.AutoHashMap([]u8, []u8).init(allocator),
            .stdin_fno = c.STDIN_FILENO,
            .stdout_fn = c.STDOUT_FILENO,
        };
    }

    pub fn execTerm(self: *Self, term: []u8, argv: [][]u8) !u8 {
        if (std.mem.equal(term, ".")) {
            // TODO: bounds checking.
            return self.execTerm(argv[0], argv[1..]);
        }

        var pid = c.fork();
        if (pid == 0) {
            if (self.stdin_fno != c.STDIN_FILENO) {
                c.close(c.STDIN_FILENO);
                c.dup(self.stdin_fno);
            }

            if (self.stdout_fno != c.STDOUT_FILENO) {
                c.close(c.STDOUT_FILENO);
                c.dup(self.stdout_fno);
            }

            c.execvp(term.ptr, argv.ptr);

            // If we got here, that means the exec failed!
            self.giveup("execTerm: exec {} failed", .{term});
        }

        self.last_pid = pid;

        var status: c_int = 0;
        pid = c.waitpid(pid, &status, 0);
        if (pid < 0) {
            self.giveup("execTerm: waitpid failed with pid={},status={}", .{ pid, status });
        }

        return @intCast(status);
    }

    pub fn exec(self: *Self, command: *cmd.Cmd) !u8 {
        var term: ?[]u8 = null;

        var args = std.ArrayList([]u8).init(self.allocator);

        // Set up executor err jump.
        var err_status = c.setjmp(self.err_jump);
        if (err_status != 0) {
            return err_status;
        }

        for (command.parts.items, 0..) |part, i| {
            switch (part) {
                .varAssign => |varAssign| {
                    const name = varAssign.name;
                    const value = try self.wordToStr(varAssign.value);

                    // If this is the only part of the command, set the var as an executor
                    // var.
                    if (i == command.parts.items.len - 1) {
                        self.vars.put(name, value);
                    }
                    // Otherwise, set it as a var for the environment for the command.
                    else {
                        command.env_vars.put(name, value);
                    }
                },

                .word => |word| {
                    const wordStr = try self.wordToString(word);
                    if (term == null) {
                        term = wordStr;
                    }

                    args.append(wordStr);
                },

                .pipedCmd => |pipedCmd| {
                    const original_fnos = [_]c_int{ self.stdin_fno, self.stdout_fno };

                    const pipe_fnos = [2]c_int{};
                    if (c.pipe(pipe_fnos) < 0) {
                        self.giveup("exec: pipe failed", .{});
                    }

                    // Build argv.
                    const argv = try ArgvHandle.fromSlice(self.allocator, args.items);
                    defer argv.deinit();

                    // Write to the write end of the pipe.
                    self.stdout_fno = pipe_fnos[1];

                    // Execute the left side.
                    const left_status = try self.execTerm(term, argv);
                    if (left_status != 0) {
                        c.close(pipe_fnos[0]);
                        c.close(pipe_fnos[1]);

                        self.stdin_fno = original_fnos[0];
                        self.stdout_fno = original_fnos[1];

                        return left_status;
                    }

                    // Close the write end of the pipe (we're done writing), restore the output fno, and read from the read end.
                    c.close(pipe_fnos[1]);
                    self.stdout_fno = original_fnos[1];
                    self.stdin_fno = pipe_fnos[0];

                    // Execute the right side.
                    const right_status = try self.exec(pipedCmd);

                    // Restore the read fno.
                    self.stdin_fno = original_fnos[0];

                    return right_status;
                },

                .orCmd => |orCmd| {
                    const argv = try ArgvHandle.fromSlice(self.allocator, args.items);
                    defer argv.deinit();

                    const left_status = try self.exec_term(term, argv);

                    // If the left side succeeded, we're done!
                    if (left_status == 0) {
                        return 0;
                    }

                    // Otherwise, execute the or'd command.
                    return try self.exec(orCmd);
                },

                .andCmd => |andCmd| {
                    const argv = try ArgvHandle.fromSlice(self.allocator, args.items);
                    defer argv.deinit();

                    const left_status = try self.exec_term(term, argv);

                    // If the left side failed, bail!
                    if (left_status == 0) {
                        return left_status;
                    }

                    // Otherwise, execute the and'd command.
                    return try self.exec(andCmd);
                },
            }
        }

        if (term == null) {
            return 0;
        }

        const argv = try ArgvHandle.fromSlice(self.allocator, args.items);
        defer argv.deinit();

        return try self.exec_term(term, argv.ptr);
    }

    fn wordToStr(self: Self, word: *cmd.CmdWord) ![]u8 {
        const res = std.ArrayList(u8).init(self.allocator);

        for (word.parts.items) |part| {
            switch (part) {
                .literal => |literal| {
                    try res.appendSlice(literal);
                },
                .str => |str| {
                    if (str.quoted) {
                        for (str.parts.items) |str_part| {
                            switch (str_part) {
                                .literal => |literal| {
                                    try res.appendSlice(literal);
                                },

                                .variable => |variable| {
                                    const val = self.getVar(variable.name);
                                    if (val != null) {
                                        res.appendSlice(val);
                                    }
                                },
                            }
                        }
                    } else {
                        for (str.parts.items) |str_part| {
                            switch (str_part) {
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
                        res.appendSlice(val);
                    }
                },

                .cmd_sub => |cmd_sub| {
                    const original_fnos = [_]c_int{ self.stdin_fno, self.stdout_fno };

                    const pipe_fnos = []c_int{0} ** 2;
                    if (c.pipe(pipe_fnos) < 0) {
                        self.giveup("wordToStr: pipe failed", .{});
                    }

                    // Write to the write end of the pipe while executing the cmd.
                    self.stdout_fno = pipe_fnos[1];
                    const status = self.exec(cmd_sub);
                    self.stdout_fno = original_fnos[1];

                    // Signal that we're done writing.
                    c.close(pipe_fnos[1]);

                    // If the command failed, bail!
                    if (status != 0) {
                        self.exitError(status);
                    }

                    // Read the result.
                    const arg = blk: {
                        const argRes = std.ArrayList(u8).init(self.allocator);

                        var buf = [_]u8{0} ** c.BUFSIZ;

                        var n = c.read(pipe_fnos[0], buf.ptr);
                        while (n != 0) {
                            if (n < c.BUFSIZ) {
                                // Remove the trailing newline.
                                buf = buf[0..n];
                                buf[n - 1] = 0;
                            }

                            argRes.appendSlice(buf);

                            n = c.read(pipe_fnos[0], buf.ptr);
                        }

                        break :blk argRes;
                    };

                    // Close the read end.
                    c.close(pipe_fnos[0]);

                    res.appendSlice(try arg.toOwnedSlice());
                },

                .proc_sub => |proc_sub| {
                    const file_name = "/tmp/turtle-proc-XXXXXX";

                    var fd = c.mkstemp(file_name);
                    if (fd < 0) {
                        self.giveup("wordToStr: proc sub file creation failed", .{});
                    }

                    if (c.chmod(file_name, 0o777) < 0) {
                        self.giveup("wordToStr: proc sub file chmod failed", .{});
                    }

                    const original_out_fd = self.stdout_fno;

                    // Write to the file during execution.
                    self.stdout_fno = fd;
                    const status = self.exec(proc_sub);
                    self.stdout_fno = original_out_fd;

                    // Signal that we're done writing to the file.
                    c.close(fd);

                    // If the command failed, bail!
                    if (status != 0) {
                        self.exitErr(status);
                    }

                    // Reopen the file with the correct flags.
                    fd = c.open(file_name, c.O_RDONLY);
                    if (fd < 0) {
                        self.giveup("wordToStr: proc sub file reopen failed", .{});
                    }

                    // Provide the filename as "/dev/fd/$FD".
                    std.fmt.format(res, "/dev/fd/{}", .{fd});
                },
            }
        }
    }

    fn getVar(self: Self, name: []u8) !?[]u8 {
        // Check if this is a special var name.
        if (std.mem.eql(u8, "!", name)) {
            std.fmt.allocPrint(self.allocator, "{}", .{self.last_pid});
        }

        // CHeck if we have a var def for the command.
        var value = self.vars.get(name);
        if (value == null) {
            // Fall back to the environment.
            value = std.os.getenv(value);
        }

        return value;
    }

    fn giveup(_: *Self, fmt: []u8, args: anytype) void {
        std.log.err("executor error: " ++ fmt, args);
        std.os.exit(1);
    }

    fn exitErr(self: *Self, status: c_int) void {
        c.longjmp(self.err_jump, status);
    }

    const ArgvHandle = struct {
        allocator: std.mem.Allocator,
        argv: ?[][*]u8,

        pub fn fromSlice(allocator: std.mem.Allocator, slice: [][]u8) !@This() {
            const argv = try allocator.allocSentinel([*]u8, slice.len, 0);
            for (slice) |arg| {
                const c_arg = try allocator.allocSentinel(u8, arg.len, 0);
                @memcpy(c_arg, arg);
            }

            .{ allocator, argv };
        }

        pub fn deinit(self: @This()) void {
            for (self.argv) |arg| {
                self.allocator.free(arg);
            }

            self.allocator.free(self.argv);
        }
    };
};
