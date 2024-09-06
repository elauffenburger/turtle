const std = @import("std");
const assert = std.debug.assert;

const cmd = @import("../parser/cmd.zig");

const proc = @import("proc.zig");
const util = @import("util.zig");
const c = util.c;

pub const ExecOpts = struct {
    stdin_fno: c_int,
    stdout_fno: c_int,
    wait: bool,
};

const ExecBuiltCmdResult = union(enum) {
    pid: i32,
    status: u8,
};

const ExecutableCmd = union(enum) {
    const Normal = struct {
        args: std.ArrayList([]u8),
        env: std.ArrayList([]u8),
    };

    const Branch = struct {
        left: ExecutableCmd,
        right: ExecutableCmd,
    };

    const Pipeline = struct {
        cmds: std.ArrayList(ExecutableCmd),
    };

    normal_cmd: Normal,

    or_cmd: *Branch,
    and_cmd: *Branch,

    pipeline: Pipeline,
};

pub const CmdExecutor = struct {
    const Self = @This();

    allocator: std.mem.Allocator,

    vars: std.StringHashMap([]u8),
    last_pid: ?c_int,
    last_status_code: ?u8,

    err_jmp_buf: ?c.jmp_buf,

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .last_pid = null,
            .last_status_code = null,
            .vars = std.StringHashMap([]u8).init(allocator),
            .err_jmp_buf = null,
        };
    }

    pub fn exec(self: *Self, command: *cmd.Cmd, opts: ExecOpts) anyerror!u8 {
        self.err_jmp_buf = [_]c_int{0} ** 48;
        if (c.setjmp(&self.err_jmp_buf.?) != 0) {
            return self.last_status_code.?;
        }

        const built_cmd = try self.buildExecutableCmd(command);
        const result = try self.execBuiltCmd(built_cmd, opts);

        self.last_status_code = result.status;
        return self.last_status_code.?;
    }

    // TODO: we should really wait until the last second to perform cmd/proc subs! This is a bit surprising because building a cmd ends up having side effects!
    fn buildExecutableCmd(self: *Self, command: *cmd.Cmd) anyerror!ExecutableCmd {
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
                    const built_or_cmd = try self.allocator.create(ExecutableCmd.Branch);
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
                    const built_and_cmd = try self.allocator.create(ExecutableCmd.Branch);
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
                        util.giveup("wordToStr: pipe failed", .{});
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
                        self.exitErr(status);
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
                        util.giveup("wordToStr: proc sub file creation failed", .{});
                    }

                    if (c.chmod(file_name_buf[0..].ptr, 0o777) < 0) {
                        util.giveup("wordToStr: proc sub file chmod failed", .{});
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
                        self.exitErr(status);
                    }

                    // Reopen the file with the correct flags.
                    fd = c.open(file_name_buf[0..].ptr, c.O_RDONLY);
                    if (fd < 0) {
                        util.giveup("wordToStr: proc sub file reopen failed", .{});
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
        if (std.mem.eql(u8, "?", name)) {
            return try std.fmt.allocPrint(self.allocator, "{d}", .{self.last_status_code.?});
        }

        // Check if we have a var def for the command.
        var value = self.vars.get(name);
        if (value == null) {
            // Fall back to the environment.
            const envVal = std.posix.getenv(name);
            if (envVal != null) {
                const buf = try self.allocator.alloc(u8, envVal.?.len);
                @memcpy(buf, envVal.?[0..envVal.?.len]);

                value = buf;
            }
        }

        return value;
    }

    // TODO: clean up memory once we're done.
    fn execBuiltCmd(self: *Self, command: ExecutableCmd, opts: ExecOpts) anyerror!ExecBuiltCmdResult {
        switch (command) {
            .normal_cmd => |normal_cmd| {
                if (normal_cmd.args.items.len == 0) {
                    return .{ .status = 0 };
                }

                const fork_exec_args = proc.ForkExecArgs{
                    .argv = normal_cmd.args.items,
                    .envp = normal_cmd.env.items,
                    .stdin_fno = opts.stdin_fno,
                    .stdout_fno = opts.stdout_fno,
                };

                if (opts.wait) {
                    return .{ .status = try proc.forkExec(self.allocator, fork_exec_args) };
                } else {
                    return .{ .pid = try proc.forkExecNoWait(self.allocator, fork_exec_args) };
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
                return try self.runPipeline(pipeline, opts);
            },
        }
    }

    fn runPipeline(self: *Self, pipeline: ExecutableCmd.Pipeline, opts: ExecOpts) !ExecBuiltCmdResult {
        const pid = c.fork();
        assert(pid != -1);
        if (pid == 0) {
            _ = c.setpgid(0, 0);

            const PipelineProcInfo = struct {
                pid: i32,
                stdin_fno: c_int,
                stdout_fno: c_int,
            };

            var pipeline_procs = std.ArrayList(PipelineProcInfo).init(self.allocator);

            // Start up each process in the pipeline.
            var prev_stdin_fno = opts.stdin_fno;
            for (pipeline.cmds.items, 0..) |pipeline_cmd, i| {
                const is_last_pipeline_proc = i == pipeline.cmds.items.len - 1;

                // TODO: make sure we don't have any in-progress args/env/etc. because that would indicate an error with the parsing (since the pipeline cmds should be self-contained).

                // Figure out what our fnos should be.
                //
                // If this is the last command in the pipeline, use the previous stdin fno, but output directly to stdout.
                // Otherwise, allocate a pipe we'll use to pipe output between procs.
                var fnos: [2]c_int = undefined;
                if (is_last_pipeline_proc) {
                    fnos = .{ prev_stdin_fno, opts.stdout_fno };
                } else {
                    var pipe_fnos = [2]c_int{ 0, 0 };
                    _ = c.pipe(&pipe_fnos);

                    fnos = .{ prev_stdin_fno, pipe_fnos[1] };

                    // Save the read end for the next pipeline proc.
                    prev_stdin_fno = pipe_fnos[0];
                }

                // Fork-exec the left side but don't wait for it.
                const exec_result = try self.execBuiltCmd(pipeline_cmd, .{
                    .stdin_fno = fnos[0],
                    .stdout_fno = fnos[1],
                    .wait = false,
                });

                _ = c.close(fnos[0]);
                _ = c.close(fnos[1]);

                // Add the left side of the pipe to the pipeline.
                try pipeline_procs.append(.{
                    .pid = exec_result.pid,
                    .stdin_fno = fnos[0],
                    .stdout_fno = fnos[1],
                });
            }

            // Close the last stdin fno.
            _ = c.close(prev_stdin_fno);

            var exit_status: u8 = 0;
            for (pipeline_procs.items, 0..) |pipeline_proc, i| {
                const status = proc.wait(pipeline_proc.pid);

                // If this proc failed, kill the rest of the procs in the pipeline and bail.
                if (status != 0) {
                    for (pipeline_procs.items[i + 1 ..]) |next_cmd| {
                        _ = c.kill(next_cmd.pid, c.SIGKILL);
                    }

                    exit_status = status;
                    break;
                }
            }

            std.posix.exit(exit_status);
        }

        const status = proc.wait(pid);
        return .{
            .status = status,
        };
    }

    fn exitErr(self: *Self, status: u8) noreturn {
        self.last_status_code = status;
        c.longjmp(&self.err_jmp_buf.?, status);
        unreachable;
    }
};
