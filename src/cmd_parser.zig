const std = @import("std");
const cmd = @import("cmd.zig");

const STR_UNQUOTED = '\'';
const STR_QUOTED = '"';
const VAR_EXPAND_START = '$';
const VAR_ASSIGN = '=';
const PIPE = '|';
const COMMENT = '#';

pub const CmdParser = struct {
    const Self = @This();

    allocator: std.mem.Allocator,

    bufOffset: usize,
    buf: []u8,
    inSub: bool,

    pub fn init(allocator: std.mem.Allocator, buf: []u8) Self {
        .{ allocator, buf, false };
    }

    /// parseVarExpand parses a variable expansion.
    ///
    /// The cursor will be placed after the var name.
    /// (e.g. "$var" will be returned and the cursor will be at "/" in "$var/baz").
    fn parseVarExpand(self: *Self) !*cmd.CmdWordPartVar {
        const part = try self.allocator.create(cmd.CmdWordPartVar);

        var ch = self.next();

        // Check for special var names.
        if (ch == '!' or ch == '?') {
            part.name = self.take(1);
            return part;
        }

        // Keep track of how many characters past the head of buf we've looked.
        //
        // We'll use this to construct the name and actually update the buf later.
        var i = 0;

        while (ch != null) {
            // If this is a non-name character, we're done!
            if (!isVarNameChar(ch)) {
                break;
            }

            i += 1;
            ch = self.peek(i);
        }

        part.name = self.take(i);
        return part;
    }

    /// parseWordLiteral parses a word literal.
    ///
    /// The cursor will be placed after at the last character of the literal
    /// (e.g. "foo" will be returned and cursor will be at ' ' in "foo bar").
    fn parseWordLiteral(self: *Self) []u8 {
        // Keep track of how many characters past the head of buf we've looked.
        //
        // We'll use this to construct the name and actually update the buf later.
        var i = 0;

        var ch = self.curr();
        while (ch != null) {
            // Check if we're done with the current substitution (if any).
            if (self.inSub and ch == ')') {
                break;
            }

            // Check if we've reached a terminating character.
            if (ch == ' ' or ch == '\n' or ch == ';') {
                break;
            }

            // If this isn't a literal character, then report an error.
            if (!isLiteralChar(ch)) {
                return self.onErr("parseWordLiteral: unexpected character {}", .{ch});
            }

            i += 1;
            ch = self.peek(i);
        }

        return self.take(i);
    }

    /// parseStringLiteral parses a string literal.
    ///
    /// The cursor will be placed at the end of the literal
    /// (e.g. "foo" will be returned and the cursor will be at '$' in "foo$bar").
    fn parseStringLiteral(self: *Self, predicate: *const fn (u8) bool) !*cmd.CmdWordPartStrPart {
        const part = try self.allocator.create(cmd.CmdWordPartStrPart);

        var i = 0;
        var ch = self.curr();
        while (ch != null) {
            if (!predicate(ch)) {
                break;
            }

            i += 1;
            ch = self.peek(i);
        }

        part.literal = self.take(i);
        return part;
    }

    /// parseStrUnquoted parses an unquoted string.
    ///
    /// The cursor will be placed after the string
    /// (e.g. "'foo'" will be returned and the cursor will be at ' ' in "'foo' bar").
    fn parseStrUnquoted(self: *Self) !*cmd.CmdWordPartStr {
        _ = self.next();

        const part = try self.allocator.create(cmd.CmdWordPartStr);
        part.quoted = false;
        part.parts.append(try self.parseStringLiteral(isStrUnquotedLitChar));

        _ = self.next();

        return part;
    }

    /// parseSub parses a command or process substitution.
    ///
    /// The cursor will be placed after the sub.
    fn parseSub(self: *Self) !*cmd.Cmd {
        const subPrefix = self.next();
        if (!(subPrefix == '$' or subPrefix == '<')) {
            self.onErr("parseSub: unexpected char in cmd sub: {}", .{subPrefix});
        }

        const openingBrace = self.next();
        if (openingBrace != '(') {
            self.onErr("parseSub: unexpected char in cmd sub: {}", .{openingBrace});
        }

        // Create a new parser that will parse the subexpression using the current buffer position.
        const subParser = Self.init(self.allocator, self.buf[self.bufOffset..]);
        subParser.inSub = true;
        const sub = try subParser.parse();

        // Skip ahead however many characters the subexpression parsing consumed.
        _ = self.take(subParser.bufOffset);

        return sub;
    }

    /// cmd_parser_parse_str_quoted parses a quoted string.
    ///
    /// The cursor will be placed after the string.
    /// (e.g. '"foo$bar"' will be returned and the cursor will be at ' ' in
    /// '"foo$bar" baz').
    fn parseStrQuoted(self: *Self) !cmd.CmdWordPartStr {
        _ = self.next();

        const res = try self.allocator.create(cmd.CmdWordPartStr);
        res.quoted = true;

        var ch = self.curr();
        while (ch != null) {
            if (isStrQuotedLitChar(ch)) {
                res.parts.append(try self.parseStringLiteral(isStrQuotedLitChar));
            } else if (ch == VAR_EXPAND_START) {
                const part = try self.allocator.create(cmd.CmdWordPartStrPart);
                part.variable = try self.parseVarExpand();

                res.parts.append(part);
            } else if (ch == STR_QUOTED) {
                _ = self.next();
            } else {
                self.onErr("parseStrQuoted: unexpected char: {}", .{ch});
            }
        }

        return res;
    }

    /// cmd_parser_parse_str parses a string.
    ///
    /// The cursor will be placed after the string.
    /// (e.g. "'foo'" will be returned and the cursor will be at ' ' in "'foo' bar").
    fn parseString(self: *Self) !*cmd.CmdWordPartStr {
        const ch = self.curr();
        switch (ch) {
            STR_UNQUOTED => {
                return self.parseStrUnquoted();
            },
            STR_QUOTED => {
                return self.parseStrQuoted();
            },
            _ => {
                self.onErr("parseStr: unexpected char in string: {}", .{ch});
            },
        }
    }

    /// cmd_parser_parse_word parses a word.
    ///
    /// The cursor will be placed after the word.
    /// (e.g. "foo" will be returned and the cursor will be at ' ' in "foo bar").
    fn parseWord(self: *Self) !*cmd.CmdWord {
        const word = try self.allocator.create(cmd.CmdWord);

        var ch = self.curr();
        while (ch != null) {
            if (ch == COMMENT) {
                self.consumeToEndOfLine();
                return word;
            }

            if (ch == ' ' or ch == '\n' or ch == ';' or (self.inSub and ch == ')')) {
                return word;
            }

            word.parts.append(blk: {
                const part = try self.allocator.create(cmd.CmdWordPart);

                // Check if this is a command sub.
                if (ch == VAR_EXPAND_START and self.peek(1) == '(') {
                    part.cmd_sub = try self.parseSub();
                }
                // Check if this is a proc sub.
                else if (ch == '<' and (self.peek(1)) == '(') {
                    part.proc_sub = try self.parseSub();
                }
                // Check if this is word literal.
                else if (isLiteralChar(ch)) {
                    part.literal = try self.parseWordLiteral();
                }
                // Check if this is a string.
                else if (ch == STR_UNQUOTED or ch == STR_QUOTED) {
                    part.str = try self.parseString();
                }
                // Check if this is a var expansion.
                else if (ch == VAR_EXPAND_START) {
                    part.variable = try self.parseVarExpand();
                } else {
                    self.onErr("parseWord: unexpected character: {}", .{ch});
                }

                break :blk part;
            });
        }
    }

    /// parse parses the init'd input and returns an executable cmd*.
    pub fn parse(self: *Self) !*cmd.Cmd {
        if (self.buf.len == 0) {
            return null;
        }

        const res = cmd.Cmd.init(self.allocator);

        var canSetVars = true;
        var ch = self.curr();

        parseLoop: while (ch != null) {
            while (ch == ' ') {
                ch = self.next();
                if (ch == null) {
                    break :parseLoop;
                }
            }

            if (ch == COMMENT) {
                self.consumeToEndOfLine();
                return res;
            }

            if (ch == '\n' or ch == ';' or (self.inSub and ch == ')')) {
                _ = self.next();
                return res;
            }

            res.parts.append(blk: {
                const part = try self.allocator.create(cmd.CmdPart);

                // Check if this is a literal word.
                if (isLiteralChar(ch) or ch == STR_UNQUOTED or ch == STR_QUOTED or ch == VAR_EXPAND_START or ch == '<') {
                    var word = try self.parseWord();

                    // Check if this is a var assignment
                    if (canSetVars and word.parts.items.len == 1 and word.parts.items[0].literal != null and self.curr() == '=') {
                        _ = self.next();

                        const varAssignment = try self.allocator.create(cmd.CmdVarAssign);
                        varAssignment.name = word.parts.items[0];
                        varAssignment.value = try self.parseWord();

                        part.varAssign = varAssignment;
                        break :blk part;
                    }

                    part.word = word;
                    break :blk part;
                }

                if (ch == '&') {
                    ch = self.next();
                    if (ch == '&') {
                        canSetVars = true;

                        _ = self.next();

                        part.andCmd = try self.parse();
                        break :blk part;
                    } else {
                        self.onErr("parse: background procs not implemented", .{});
                    }
                }

                if (ch == PIPE) {
                    canSetVars = true;

                    ch = self.next();
                    if (ch == PIPE) {
                        _ = self.next();

                        part.orCmd = try self.parse();
                        break :blk part;
                    }

                    part.pipedCmd = try self.parse();
                    break :blk part;
                }

                self.onErr("parse: unexpected char {}", .{ch});
            });
        }

        return res;
    }

    fn consumeToEndOfLine(self: *Self) !void {
        var ch = self.curr();
        while (ch != null and !isEndOfLine(ch)) {
            _ = self.next();
        }
    }

    fn next(self: *Self) ?u8 {
        const taken = self.take(1);
        if (taken == null) {
            return null;
        }

        return taken[0];
    }

    fn take(self: *Self, offset: usize) ?[]u8 {
        const newOffset = self.bufOffset + offset;
        if (newOffset >= self.buf.len) {
            return null;
        }

        const result = self.buf[self.bufOffset..newOffset];
        self.bufOffset = newOffset;

        return result;
    }

    fn curr(self: Self) ?u8 {
        return self.peek(0);
    }

    fn peek(self: Self, offset: usize) ?u8 {
        const actualOffset = self.bufOffset + offset;

        if (actualOffset < self.buf.len) {
            return self.buf[actualOffset];
        } else {
            return null;
        }
    }

    fn onErr(_: *Self, fmt: []u8, args: anytype) void {
        std.log.err("parser error: " ++ fmt, args);
        std.os.exit(1);
    }
};

fn isAlpha(ch: u8) bool {
    return (ch >= 'a' and ch <= 'z') || (ch >= 'A' and ch <= 'Z');
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
