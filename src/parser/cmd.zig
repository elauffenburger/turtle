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

pub const CmdVar = struct {
    name: []u8,
    value: *CmdWord,
};

pub const CmdPart = union(enum) {
    word: *CmdWord,
    var_assign: *CmdVar,
    pipeline: std.ArrayList(*Cmd),
    or_cmd: *Cmd,
    and_cmd: *Cmd,
};

pub const CmdWord = struct {
    parts: std.ArrayList(*CmdWordPart),

    pub fn init(allocator: std.mem.Allocator) @This() {
        return .{ .parts = std.ArrayList(*CmdWordPart).init(allocator) };
    }
};

pub const CmdWordPart = union(enum) {
    literal: []u8,
    str: *CmdWordPartStr,
    variable: *CmdWordPartVar,
    cmd_sub: *Cmd,
    proc_sub: *Cmd,
};

pub const CmdWordPartStr = struct {
    expandable: bool,
    parts: std.ArrayList(CmdWordPartStrPart),

    pub fn init(allocator: std.mem.Allocator, expandable: bool) @This() {
        return .{
            .expandable = expandable,
            .parts = std.ArrayList(CmdWordPartStrPart).init(allocator),
        };
    }
};

pub const CmdWordPartStrPart = union(enum) {
    literal: []u8,
    variable: *CmdWordPartVar,
};

pub const CmdWordPartVar = struct {
    name: []u8,
};
