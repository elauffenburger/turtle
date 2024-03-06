const std = @import("std");

pub const Cmd = struct {
    parts: std.ArrayList(CmdPart),
    env_vars: std.AutoHashMap([]u8, []u8),

    pub fn init(allocator: std.mem.Allocator) @This() {
        .{ std.ArrayList(CmdPart).init(allocator), std.AutoArrayHashMap([]u8, []u8).init(allocator) };
    }

    pub fn deinit(self: @This()) void {
        for (self.parts) |part| {
            part.deinit();
        }

        self.parts.deinit();
        self.env_vars.deinit();
    }
};

pub const CmdVarAssign = struct {
    name: []u8,
    value: *CmdWord,

    pub fn deinit(self: @This()) void {
        self.value.deinit();
    }
};

pub const CmdPartType = enum {
    word,
    varAssign,
    pipedCmd,
    orCmd,
    andCmd,
};

pub const CmdPart = union(CmdPartType) {
    word: *CmdWord,
    varAssign: *CmdVarAssign,
    pipedCmd: *Cmd,
    orCmd: *Cmd,
    andCmd: *Cmd,

    pub fn deinit(self: @This()) void {
        switch (self) {
            .word => |word| {
                word.deinit();
            },
            .varAssign => |varAssign| {
                varAssign.deinit();
            },
            .pipedCmd => |pipedCmd| {
                pipedCmd.deinit();
            },
            .orCmd => |cmd| {
                cmd.deinit();
            },
            .andCmd => |cmd| {
                cmd.deinit();
            },
        }
    }
};

pub const CmdWord = struct {
    parts: std.ArrayList(CmdWordPart),

    pub fn init(allocator: std.mem.Allocator) @This() {
        .{std.ArrayList(CmdWordPart).init(allocator)};
    }

    pub fn deinit(self: @This()) void {
        for (self.parts) |part| {
            part.deinit();
        }

        self.parts.deinit();
    }
};

pub const CmdWordPartType = enum {
    literal,
    str,
    variable,
    cmd_sub,
    proc_sub,
};

pub const CmdWordPart = union(CmdWordPartType) {
    literal: []u8,
    str: *CmdWordPartStr,
    variable: *CmdWordPartVar,
    cmd_sub: *Cmd,
    proc_sub: *Cmd,

    pub fn deinit(self: @This()) void {
        switch (self) {
            .literal => {},
            .str => |str| {
                str.deinit();
            },
            .variable => |variable| {
                variable.deinit();
            },
            .cmd_sub => |cmd| {
                cmd.deinit();
            },
            .proc_sub => |cmd| {
                cmd.deinit();
            },
        }
    }
};

pub const CmdWordPartStr = struct {
    quoted: bool,
    parts: std.ArrayList(CmdWordPartStrPart),

    pub fn init(allocator: std.mem.Allocator, quoted: bool) @This() {
        .{ quoted, std.ArrayList(CmdWordPartStr).init(allocator) };
    }

    pub fn deinit(self: @This()) void {
        for (self.parts) |part| {
            part.deinit();
        }

        self.parts.deinit();
    }
};

pub const CmdWordPartStrPartType = enum {
    literal,
    variable,
};

pub const CmdWordPartStrPart = union(CmdWordPartStrPartType) {
    literal: []u8,
    variable: *CmdWordPartVar,

    pub fn deinit(self: @This()) void {
        switch (self) {
            .literal => {},
            .variable => |variable| {
                variable.deinit();
            },
        }
    }
};

pub const CmdWordPartVar = struct {
    name: []u8,
};
