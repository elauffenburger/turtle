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
    last_pid: ?c_int,
    exit_status_code: ?u8,

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .last_pid = null,
            .vars = std.StringHashMap([]u8).init(allocator),
            .exit_status_code = null,
        };
    }

    const ExecutableCmdBranch = struct {
        left: ExecutableCmd,
        right: ExecutableCmd,
    };

    const ExecutableCmdTag = enum {
        normal_cmd,
        or_cmd,
        and_cmd,
        pipeline,
    };

    const ExecutableCmd = union(ExecutableCmdTag) {
        normal_cmd: struct {
            args: std.ArrayList([]u8),
            env: std.ArrayList([]u8),
        },

        or_cmd: *ExecutableCmdBranch,
        and_cmd: *ExecutableCmdBranch,

        pipeline: struct {
            cmds: std.ArrayList(ExecutableCmd),
        },
    };

    // TODO: we should really wait until the last second to perform cmd/proc subs! This is a bit surprising because building a cmd ends up having side effects!
    pub fn buildExecutableCmd(self: *Self, command: *cmd.Cmd) anyerror!ExecutableCmd {
        var args = std.ArrayList([]u8).init(self.allocator);
        const env = std.ArrayList([]u8).init(self.allocator);

        // Set up executor err jump.
        for (command.parts.items, 0..) |part, i| {
            switch (part) {
                .var_assign => |var_assign| {
                    const name = var_assign.name;
                    const value = try self.wordToStr(var_assign.value);

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

                .pipeline => |pipeline_cmds| {
                    // TODO: check if there are any args/env/vars/etc.; that's probably an error with parsing if so!

                    var pipeline = try std.ArrayList(ExecutableCmd).initCapacity(self.allocator, pipeline_cmds.items.len);
                    for (pipeline_cmds.items) |pipeline_cmd| {
                        try pipeline.append(try self.buildExecutableCmd(pipeline_cmd));
                    }

                    return .{
                        .pipeline = .{
                            .cmds = pipeline,
                        },
                    };
                },

                .or_cmd => |or_cmd| {
                    const built_or_cmd = try self.allocator.create(ExecutableCmdBranch);
                    built_or_cmd.* = .{
                        .left = .{
                            .normal_cmd = .{
                                .args = args,
                                .env = env,
                            },
                        },
                        .right = try self.buildExecutableCmd(or_cmd),
                    };

                    return .{ .or_cmd = built_or_cmd };
                },

                .and_cmd => |and_cmd| {
                    const built_and_cmd = try self.allocator.create(ExecutableCmdBranch);
                    built_and_cmd.* = .{
                        .left = .{
                            .normal_cmd = .{
                                .args = args,
                                .env = env,
                            },
                        },
                        .right = try self.buildExecutableCmd(and_cmd),
                    };

                    return .{ .and_cmd = built_and_cmd };
                },
            }
        }

        return .{
            .normal_cmd = .{
                .args = args,
                .env = env,
            },
        };
    }

    pub const ExecOpts = struct {
        stdin_fno: c_int,
        stdout_fno: c_int,
        wait: bool,
    };

    const ExecBuiltCmdResult = union {
        pid: i32,
        status: u8,
    };

    // TODO: clean up memory once we're done.
    fn execBuiltCmd(self: *Self, command: ExecutableCmd, opts: ExecOpts) anyerror!ExecBuiltCmdResult {
        switch (command) {
            .normal_cmd => |normal_cmd| {
                if (normal_cmd.args.items.len == 0) {
                    return .{ .status = 0 };
                }

                const fork_exec_args = ForkExecArgs{
                    .argv = normal_cmd.args.items,
                    .envp = normal_cmd.env.items,
                    .stdin_fno = opts.stdin_fno,
                    .stdout_fno = opts.stdout_fno,
                };

                if (opts.wait) {
                    return .{ .status = try self.forkExec(fork_exec_args) };
                } else {
                    return .{ .pid = try self.forkExecNoWait(fork_exec_args) };
                }
            },
            .or_cmd => |or_cmd| {
                const left_status = try self.execBuiltCmd(or_cmd.left, opts);

                // If the left side succeeded, we're done!
                if (left_status.status == 0) {
                    return left_status;
                }

                // Otherwise, execute the or'd commnd.
                return try self.execBuiltCmd(or_cmd.right, opts);
            },
            .and_cmd => |or_cmd| {
                const left_status = try self.execBuiltCmd(or_cmd.left, opts);

                // If the left side failed, we're done!
                if (left_status.status != 0) {
                    return left_status;
                }

                // Otherwise, keep going!
                return try self.execBuiltCmd(or_cmd.right, opts);
            },
            .pipeline => |pipeline| {
                const PipelineCmdInfo = struct {
                    pid: i32,
                    stdin_fno: c_int,
                    stdout_fno: c_int,
                };

                var pipeline_cmds = std.ArrayList(PipelineCmdInfo).init(self.allocator);

                // Start up each process in the pipeline.
                var stdin_fno = opts.stdin_fno;
                for (pipeline.cmds.items, 0..) |pipeline_cmd, i| {
                    // TODO: make sure we don't have any in-progress args/env/etc. because that would indicate an error with the parsing (since the pipeline cmds should be self-contained).

                    // Figure out what our fnos should be.
                    //
                    // If this is the last command in the pipeline, use the previous stdin fno, but output directly to stdout.
                    // Otherwise, allocate a pipe we'll use to pipe output between procs.
                    var fnos: [2]c_int = undefined;
                    if (i == pipeline.cmds.items.len - 1) {
                        fnos = .{ stdin_fno, opts.stdout_fno };
                    } else {
                        var pipe_fnos = [2]c_int{ 0, 0 };
                        _ = c.pipe(&pipe_fnos);

                        fnos = .{ opts.stdin_fno, pipe_fnos[1] };

                        // Save the read end for later.
                        stdin_fno = pipe_fnos[0];
                    }

                    // TODO: create all procs in the pipeline in a separate proc group.
                    // Fork-exec the left side but don't wait for it.
                    const exec_result = try self.execBuiltCmd(pipeline_cmd, .{
                        .stdin_fno = fnos[0],
                        .stdout_fno = fnos[1],
                        .wait = false,
                    });

                    const pipeline_cmd_info = PipelineCmdInfo{
                        .pid = exec_result.pid,
                        .stdin_fno = fnos[0],
                        .stdout_fno = fnos[1],
                    };

                    // Add the left side of the pipe to the pipeline.
                    try pipeline_cmds.append(pipeline_cmd_info);
                }

                var exit_status: u8 = 0;
                for (pipeline_cmds.items) |pipeline_cmd| {
                    const status = Self.wait(pipeline_cmd.pid);

                    // TODO: gracefully clean up other procs.
                    if (status != 0) {
                        exit_status = status;
                    }
                }

                // Close the last stdin fno.
                _ = c.close(stdin_fno);

                return .{ .status = exit_status };
            },
        }
    }

    pub fn exec(self: *Self, command: *cmd.Cmd, opts: ExecOpts) anyerror!u8 {
        const built_cmd = try self.buildExecutableCmd(command);
        const result = try self.execBuiltCmd(built_cmd, opts);

        return result.status;
    }

    fn wordToStr(self: *Self, word: *cmd.CmdWord) anyerror![]u8 {
        var res = std.ArrayList(u8).init(self.allocator);

        for (word.parts.items) |part| {
            switch (part.*) {
                .literal => |literal| {
                    try res.appendSlice(literal);
                },
                .str => |str| {
                    if (str.expandable) {
                        for (str.parts.items) |str_part| {
                            switch (str_part) {
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
                        try res.appendSlice(val.?);
                    }
                },

                .cmd_sub => |cmd_sub| {
                    var pipe_fnos = [2]c_int{ 0, 0 };
                    if (c.pipe(&pipe_fnos) < 0) {
                        self.giveup("wordToStr: pipe failed", .{});
                    }

                    // Write to the write end of the pipe while executing the cmd.
                    const status = try self.exec(cmd_sub, .{
                        .stdin_fno = std.posix.STDIN_FILENO,
                        .stdout_fno = pipe_fnos[1],
                        .wait = true,
                    });

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

                    // Write to the file during execution.
                    const maybeStatus = self.exec(proc_sub, .{
                        .stdin_fno = std.posix.STDIN_FILENO,
                        .stdout_fno = fd,
                        .wait = true,
                    });

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
            const envVal = std.posix.getenv(name);
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
        std.posix.exit(1);
    }

    fn exitErr(self: *Self, status: u32) Error!void {
        self.exit_status_code = @intCast(status);
    }

    const ForkExecArgs = struct {
        argv: [][]u8,
        envp: [][]u8,
        stdin_fno: c_int,
        stdout_fno: c_int,
    };

    fn replaceFd(old: c_int, new: c_int) void {
        _ = c.dup2(old, new);
        _ = c.close(old);
    }

    fn forkExecNoWait(self: *Self, args: ForkExecArgs) !i32 {
        const pid = try std.posix.fork();
        if (pid == 0) {
            if (args.stdin_fno != c.STDIN_FILENO) {
                replaceFd(args.stdin_fno, std.posix.STDIN_FILENO);
            }

            if (args.stdout_fno != c.STDOUT_FILENO) {
                replaceFd(args.stdout_fno, std.posix.STDOUT_FILENO);
            }

            const argv = try toCStringVec(self.allocator, args.argv);
            // defer self.allocator.destroy(argv.ptr);

            const envp = try toCStringVec(self.allocator, args.envp);
            // defer self.allocator.destroy(envp);

            // Finally run this thing.
            const err = std.posix.execvpeZ(argv[0].?, argv, envp);

            // If we got here, that means the exec failed!
            self.giveup("execTerm: exec {s} failed: {any}", .{ args.argv[0], err });
        }

        return pid;
    }

    fn forkExec(self: *Self, args: ForkExecArgs) !u8 {
        return Self.wait(try self.forkExecNoWait(args));
    }

    fn wait(pid: i32) u8 {
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
};
