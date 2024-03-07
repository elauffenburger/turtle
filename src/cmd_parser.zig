const std = @import("std");
const cmd = @import("cmd.zig");

const STR_UNQUOTED = '\'';
const STR_QUOTED = '"';
const VAR_EXPAND_START = '$';
const VAR_ASSIGN = '=';
const PIPE = '|';
const COMMENT = '#';

pub const Error = error{
    OutOfInput,
    NotStarted,
};

pub const CmdParser = struct {
    const Self = @This();

    allocator: std.mem.Allocator,

    buf_offset: usize,
    buf: []u8,
    in_sub: bool,
    started: bool,

    pub fn init(allocator: std.mem.Allocator, buf: []u8) Self {
        return .{
            .allocator = allocator,
            .buf_offset = 0,
            .buf = buf,
            .in_sub = false,
            .started = false,
        };
    }

    /// parseVarExpand parses a variable expansion.
    ///
    /// The cursor will be placed after the var name.
    /// (e.g. "$var" will be returned and the cursor will be at "/" in "$var/baz").
    fn parseVarExpand(self: *Self) !*cmd.CmdWordPartVar {
        const part = try self.allocator.create(cmd.CmdWordPartVar);

        var ch = try self.next();

        // Check for special var names.
        if (ch == '!' or ch == '?') {
            part.name = try self.take(1);
            return part;
        }

        // Keep track of how many characters past the head of buf we've looked.
        //
        // We'll use this to construct the name and actually update the buf later.
        var i: u32 = 0;

        while (true) {
            // If this is a non-name character, we're done!
            if (!isVarNameChar(ch)) {
                break;
            }

            i += 1;
            ch = try self.peek(i);
        }

        part.name = try self.take(i);
        return part;
    }

    /// parseWordLiteral parses a word literal.
    ///
    /// The cursor will be placed after at the last character of the literal
    /// (e.g. "foo" will be returned and cursor will be at ' ' in "foo bar").
    fn parseWordLiteral(self: *Self) Error![]u8 {
        // Keep track of how many characters past the head of buf we've looked.
        //
        // We'll use this to construct the name and actually update the buf later.
        var i: u32 = 0;

        var ch = try self.curr();
        while (true) {
            // Check if we're done with the current substitution (if any).
            if (self.in_sub and ch == ')') {
                break;
            }

            // Check if we've reached a terminating character.
            if (ch == ' ' or ch == '\n' or ch == ';') {
                break;
            }

            // If this isn't a literal character, then report an error.
            if (!isLiteralChar(ch)) {
                self.onErr("parseWordLiteral: unexpected character {s}", .{ch});
            }

            i += 1;
            ch = self.peek(i) catch break;
        }

        return try self.take(i);
    }

    /// parseStringLiteral parses a string literal.
    ///
    /// The cursor will be placed at the end of the literal
    /// (e.g. "foo" will be returned and the cursor will be at '$' in "foo$bar").
    fn parseStringLiteral(self: *Self, predicate: *const fn (u8) bool) !*cmd.CmdWordPartStrPart {
        const part = try self.allocator.create(cmd.CmdWordPartStrPart);

        var i: u32 = 0;
        var ch = try self.curr();
        while (true) {
            if (!predicate(ch)) {
                break;
            }

            i += 1;
            ch = try self.peek(i);
        }

        part.literal = try self.take(i);
        return part;
    }

    /// parseStrUnquoted parses an unquoted string.
    ///
    /// The cursor will be placed after the string
    /// (e.g. "'foo'" will be returned and the cursor will be at ' ' in "'foo' bar").
    fn parseStrUnquoted(self: *Self) !*cmd.CmdWordPartStr {
        _ = try self.next();

        const part = try self.allocator.create(cmd.CmdWordPartStr);
        part.quoted = false;
        try part.parts.append(try self.parseStringLiteral(isStrUnquotedLitChar));

        _ = try self.next();

        return part;
    }

    /// parseSub parses a command or process substitution.
    ///
    /// The cursor will be placed after the sub.
    fn parseSub(self: *Self) anyerror!*cmd.Cmd {
        const subPrefix = try self.next();
        if (!(subPrefix == '$' or subPrefix == '<')) {
            self.onErr("parseSub: unexpected char in cmd sub: {s}", .{subPrefix});
        }

        const openingBrace = try self.next();
        if (openingBrace != '(') {
            self.onErr("parseSub: unexpected char in cmd sub: {s}", .{openingBrace});
        }

        // Create a new parser that will parse the subexpression using the current buffer position.
        var subParser = Self.init(self.allocator, self.buf[self.buf_offset..]);
        subParser.in_sub = true;
        const sub = try subParser.parse();

        // Skip ahead however many characters the subexpression parsing consumed.
        _ = try self.take(subParser.buf_offset);

        return sub;
    }

    /// cmd_parser_parse_str_quoted parses a quoted string.
    ///
    /// The cursor will be placed after the string.
    /// (e.g. '"foo$bar"' will be returned and the cursor will be at ' ' in
    /// '"foo$bar" baz').
    fn parseStrQuoted(self: *Self) !*cmd.CmdWordPartStr {
        _ = try self.next();

        const res = try self.allocator.create(cmd.CmdWordPartStr);
        res.* = cmd.CmdWordPartStr.init(self.allocator, true);

        var ch = try self.curr();
        while (true) {
            if (isStrQuotedLitChar(ch)) {
                try res.parts.append(try self.parseStringLiteral(isStrQuotedLitChar));
            } else if (ch == VAR_EXPAND_START) {
                const part = try self.allocator.create(cmd.CmdWordPartStrPart);
                part.variable = try self.parseVarExpand();

                try res.parts.append(part);
            } else if (ch == STR_QUOTED) {
                _ = try self.next();
            } else {
                self.onErr("parseStrQuoted: unexpected char: {s}", .{ch});
            }

            ch = try self.curr();
        }

        return res;
    }

    /// cmd_parser_parse_str parses a string.
    ///
    /// The cursor will be placed after the string.
    /// (e.g. "'foo'" will be returned and the cursor will be at ' ' in "'foo' bar").
    fn parseString(self: *Self) anyerror!*cmd.CmdWordPartStr {
        const ch = try self.curr();
        switch (ch) {
            STR_UNQUOTED => {
                return self.parseStrUnquoted();
            },
            STR_QUOTED => {
                return self.parseStrQuoted();
            },
            else => {
                self.onErr("parseStr: unexpected char in string: {s}", .{ch});
                unreachable;
            },
        }
    }

    /// cmd_parser_parse_word parses a word.
    ///
    /// The cursor will be placed after the word.
    /// (e.g. "foo" will be returned and the cursor will be at ' ' in "foo bar").
    fn parseWord(self: *Self) !*cmd.CmdWord {
        const word = try self.allocator.create(cmd.CmdWord);
        word.* = cmd.CmdWord.init(self.allocator);

        var ch = try self.curr();
        while (true) {
            if (ch == COMMENT) {
                try self.consumeToEndOfLine();
                return word;
            }

            if (ch == ' ' or ch == '\n' or ch == ';' or (self.in_sub and ch == ')')) {
                return word;
            }

            var part = try self.allocator.create(cmd.CmdWordPart);
            part.* = blk: {
                // Check if this is a command sub.
                if (ch == VAR_EXPAND_START and try self.peek(1) == '(') {
                    break :blk cmd.CmdWordPart{
                        .cmd_sub = try self.parseSub(),
                    };
                }
                // Check if this is a proc sub.
                else if (ch == '<' and (try self.peek(1)) == '(') {
                    break :blk cmd.CmdWordPart{
                        .proc_sub = try self.parseSub(),
                    };
                }
                // Check if this is word literal.
                else if (isLiteralChar(ch)) {
                    break :blk cmd.CmdWordPart{
                        .literal = try self.parseWordLiteral(),
                    };
                }
                // Check if this is a string.
                else if (ch == STR_UNQUOTED or ch == STR_QUOTED) {
                    break :blk cmd.CmdWordPart{
                        .str = try self.parseString(),
                    };
                }
                // Check if this is a var expansion.
                else if (ch == VAR_EXPAND_START) {
                    break :blk cmd.CmdWordPart{
                        .variable = try self.parseVarExpand(),
                    };
                } else {
                    self.onErr("parseWord: unexpected character: {s}", .{ch});
                }
            };

            try word.parts.append(part);
            ch = self.curr() catch break;
        }

        return word;
    }

    /// parse parses the init'd input and returns an executable cmd*.
    pub fn parse(self: *Self) anyerror!*cmd.Cmd {
        const res = try self.allocator.create(cmd.Cmd);
        res.* = cmd.Cmd.init(self.allocator);

        var canSetVars = true;
        var ch = try self.curr();

        while (true) {
            if (isEndOfLine(ch)) {
                break;
            }

            while (ch == ' ') {
                ch = self.next() catch break;
            }

            if (ch == COMMENT) {
                self.consumeToEndOfLine() catch break;
                break;
            }

            if (ch == '\n' or ch == ';' or (self.in_sub and ch == ')')) {
                _ = self.next() catch break;
                return res;
            }

            try res.parts.append(blk: {
                // Check if this is a literal word.
                if (isLiteralChar(ch) or ch == STR_UNQUOTED or ch == STR_QUOTED or ch == VAR_EXPAND_START or ch == '<') {
                    var word = try self.parseWord();

                    // Check if this is a var assignment.
                    if (canSetVars and word.parts.items.len == 1 and word.parts.items[0].literal.len > 0 and self.curr() catch ' ' == '=') {
                        _ = try self.next();

                        const varAssignment = try self.allocator.create(cmd.CmdVarAssign);
                        varAssignment.name = word.parts.items[0].literal;
                        varAssignment.value = try self.parseWord();

                        break :blk .{ .varAssign = varAssignment };
                    }

                    break :blk .{ .word = word };
                }

                if (ch == '&') {
                    ch = try self.next();
                    if (ch == '&') {
                        canSetVars = true;

                        _ = try self.next();

                        break :blk .{ .andCmd = try self.parse() };
                    } else {
                        self.onErr("parse: background procs not implemented", .{});
                    }
                }

                if (ch == PIPE) {
                    canSetVars = true;

                    ch = try self.next();
                    if (ch == PIPE) {
                        _ = try self.next();

                        break :blk .{ .orCmd = try self.parse() };
                    }

                    break :blk .{ .pipedCmd = try self.parse() };
                }

                self.onErr("parse: unexpected char {s}", .{ch});
                unreachable;
            });

            ch = self.curr() catch break;
        }

        return res;
    }

    fn consumeToEndOfLine(self: *Self) !void {
        var ch = try self.curr();
        while (!isEndOfLine(ch)) {
            _ = try self.next();
        }
    }

    fn next(self: *Self) Error!u8 {
        self.buf_offset += 1;
        return self.buf[self.buf_offset];
    }

    /// take consumes n many characters from the input buffer.
    ///
    /// Notes:
    ///   - The result will contain the current character.
    ///   - n will be clamped so that the returned slice never exceeds the length of the buffer.
    fn take(self: *Self, n: usize) Error![]u8 {
        var newOffset = self.buf_offset + n;
        if (newOffset >= self.buf.len) {
            newOffset = self.buf.len;
        }

        const result = self.buf[self.buf_offset..newOffset];
        self.buf_offset = newOffset;

        return result;
    }

    fn curr(self: Self) Error!u8 {
        return self.peek(0);
    }

    fn peek(self: Self, offset: usize) Error!u8 {
        var effectiveOffset = self.buf_offset + offset;

        if (effectiveOffset >= 0 and effectiveOffset < self.buf.len) {
            return self.buf[effectiveOffset];
        } else {
            return Error.OutOfInput;
        }
    }

    fn onErr(_: *Self, _: []const u8, _: anytype) noreturn {
        // std.log.err(fmt, args);
        std.os.exit(1);
    }
};

fn isAlpha(ch: u8) bool {
    return (ch >= 'a' and ch <= 'z') or (ch >= 'A' and ch <= 'Z');
}

fn isNumeric(ch: u8) bool {
    return ch >= 48 and ch <= 57;
}

fn isLiteralChar(ch: u8) bool {
    return !(ch == ' ' or ch == '\n' or ch == '$' or ch == '`' or ch == '<' or
        ch == '>' or ch == '&' or ch == STR_QUOTED or ch == STR_UNQUOTED or
        ch == PIPE or ch == ';');
}

fn isVarNameChar(ch: u8) bool {
    return isAlpha(ch) or isNumeric(ch) or ch == '_';
}

fn isEndOfLine(ch: u8) bool {
    return ch == '\n' or ch == 0;
}

fn isStrUnquotedLitChar(ch: u8) bool {
    return ch != STR_UNQUOTED;
}

fn isStrQuotedLitChar(ch: u8) bool {
    return isLiteralChar(ch) or ch == ' ' or ch == ';';
}
