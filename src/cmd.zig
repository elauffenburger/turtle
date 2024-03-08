const std = @import("std");

pub const Cmd = struct {
    parts: std.ArrayList(CmdPart),
    env_vars: std.StringHashMap([]u8),

    pub fn init(allocator: std.mem.Allocator) @This() {
        return .{
            .parts = std.ArrayList(CmdPart).init(allocator),
            .env_vars = std.StringHashMap([]u8).init(allocator),
        };
    }
};

pub const CmdVarAssign = struct {
    name: []u8,
    value: *CmdWord,
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
};

pub const CmdWord = struct {
    parts: std.ArrayList(*CmdWordPart),

    pub fn init(allocator: std.mem.Allocator) @This() {
        return .{ .parts = std.ArrayList(*CmdWordPart).init(allocator) };
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
};

pub const CmdWordPartStr = struct {
    quoted: bool,
    parts: std.ArrayList(*CmdWordPartStrPart),

    pub fn init(allocator: std.mem.Allocator, quoted: bool) @This() {
        return .{
            .quoted = quoted,
            .parts = std.ArrayList(*CmdWordPartStrPart).init(allocator),
        };
    }
};

pub const CmdWordPartStrPartType = enum {
    literal,
    variable,
};

pub const CmdWordPartStrPart = union(CmdWordPartStrPartType) {
    literal: []u8,
    variable: *CmdWordPartVar,
};

pub const CmdWordPartVar = struct {
    name: []u8,
};