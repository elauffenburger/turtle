const std = @import("std");

pub const Cmd = struct {
    parts: std.ArrayList(CmdPart),

    pub fn init(allocator: std.mem.Allocator) @This() {
        return .{
            .parts = std.ArrayList(CmdPart).init(allocator),
        };
    }

    pub fn jsonStringify(self: *const Cmd, jws: anytype) !void {
        try jws.beginObject();
        try jws.objectField("cmd");
        try jws.beginObject();
        try jws.objectField("parts");
        try jws.beginArray();
        for (self.parts.items) |part| {
            try part.jsonStringify(jws);
        }
        try jws.endArray();
        try jws.endObject();
        try jws.endObject();
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

    pub fn jsonStringify(self: *const CmdPart, jws: anytype) @TypeOf(jws.*).Error!void {
        try jws.beginObject();
        switch (self.*) {
            .word => |word| {
                try jws.objectField("word");
                try word.jsonStringify(jws);
            },
            .var_assign => |var_assign| {
                try jws.objectField("var_assign");

                try jws.beginObject();
                try jws.objectField("name");
                try jws.write(var_assign.name);
                try jws.objectField("value");
                try var_assign.value.jsonStringify(jws);
                try jws.endObject();
            },
            .pipeline => |pipeline| {
                try jws.objectField("pipeline");
                try jws.beginArray();
                for (pipeline.items) |item| {
                    try item.jsonStringify(jws);
                }
                try jws.endArray();
            },
            .or_cmd => |or_cmd| {
                try jws.objectField("or_cmd");
                try or_cmd.jsonStringify(jws);
            },
            .and_cmd => |and_cmd| {
                try jws.objectField("and_cmd");
                try and_cmd.jsonStringify(jws);
            },
        }
        try jws.endObject();
    }
};

pub const CmdWord = struct {
    parts: std.ArrayList(*CmdWordPart),

    pub fn init(allocator: std.mem.Allocator) @This() {
        return .{ .parts = std.ArrayList(*CmdWordPart).init(allocator) };
    }

    pub fn jsonStringify(self: *const CmdWord, jws: anytype) !void {
        try jws.beginObject();

        try jws.objectField("parts");
        try jws.beginArray();
        for (self.parts.items) |word_part| {
            switch (word_part.*) {
                .literal => |literal| {
                    try jws.beginObject();

                    try jws.objectField("literal");
                    try jws.write(literal);

                    try jws.endObject();
                },
                .str => |str| {
                    try jws.beginObject();
                    try jws.objectField("str");

                    try jws.beginObject();
                    try jws.objectField("parts");
                    try jws.beginArray();
                    for (str.parts.items) |str_part| {
                        try jws.beginObject();
                        switch (str_part) {
                            .literal => |literal| {
                                try jws.objectField("literal");
                                try jws.write(literal);
                            },
                            .variable => |variable| {
                                try jws.objectField("variable");
                                try jws.beginObject();
                                try jws.objectField("name");
                                try jws.write(variable.name);
                                try jws.endObject();
                            },
                        }
                        try jws.endObject();
                    }
                    try jws.endArray();
                    try jws.endObject();

                    try jws.endObject();
                },
                .variable => |variable| {
                    try jws.beginObject();
                    try jws.objectField("variable");

                    try jws.beginObject();
                    try jws.objectField("name");
                    try jws.write(variable.name);
                    try jws.endObject();

                    try jws.endObject();
                },
                .cmd_sub => |cmd_sub| {
                    try jws.beginObject();
                    try jws.objectField("cmd_sub");
                    try cmd_sub.jsonStringify(jws);
                    try jws.endObject();
                },
                .proc_sub => |proc_sub| {
                    try jws.beginObject();
                    try jws.objectField("proc_sub");
                    try proc_sub.jsonStringify(jws);
                    try jws.endObject();
                },
            }
        }
        try jws.endArray();

        try jws.endObject();
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
