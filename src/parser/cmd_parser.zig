const std = @import("std");
const cmd = @import("cmd.zig");

pub usingnamespace cmd;

pub const STR_SINGLE_QUOTE = '\'';
pub const STR_DOUBLE_QUOTE = '"';
pub const VAR_EXPAND_START = '$';
pub const VAR_ASSIGN = '=';
pub const PIPE = '|';
pub const COMMENT = '#';

pub const ParseError = error{
    EOF,
};

pub const CmdParser = struct {
    const Self = @This();

    allocator: std.mem.Allocator,

    buf_offset: usize,
    buf: []u8,
    in_sub: bool,
    in_pipeline: bool,
    can_set_vars: bool,

    pub fn init(allocator: std.mem.Allocator, buf: []u8) Self {
        return .{
            .allocator = allocator,
            .buf_offset = 0,
            .buf = buf,
            .in_sub = false,
            .in_pipeline = false,
            .can_set_vars = false,
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
            ch = self.peek(i) catch break;
        }

        part.name = try self.take(i);
        return part;
    }

    /// parseWordLiteral parses a word literal.
    ///
    /// The cursor will be placed after at the last character of the literal
    /// (e.g. "foo" will be returned and cursor will be at ' ' in "foo bar").
    fn parseWordLiteral(self: *Self) ParseError![]u8 {
        // Keep track of how many characters past the head of buf we've looked.
        //
        // We'll use this to construct the name and actually update the buf later.
        var i: u32 = 0;

        var ch = try self.curr();
        while (true) {
            // If one of the following is true, we're done!
            //  * ch is an "end of word" character
            //  * we're in a substitution and ch is the end of the substitution
            //  * we can currently set vars and ch is an '='
            if (self.isEndOfWordChar(ch)) {
                break;
            }

            // If this isn't a literal character, then report an error.
            if (!isLiteralChar(ch)) {
                giveup("parseWordLiteral: unexpected character {any}", .{ch});
            }

            i += 1;
            ch = self.peek(i) catch break;
        }

        return try self.take(i);
    }

    /// parseStringLiteral parses a string literal.
    ///
    /// The cursor will be placed at the end of the literal.
    /// examples:
    /// ```
    /// _: returned char
    /// ^: the position of the cursor after returning
    ///
    /// "foobar"
    ///  ______^
    ///
    /// "foo$bar"
    ///  ___^
    /// ```
    fn parseStringLiteral(self: *Self, predicate: *const fn (u8) bool) !cmd.CmdWordPartStrPart {
        var i: u32 = 0;
        var ch = try self.curr();
        while (true) {
            if (!predicate(ch)) {
                break;
            }

            i += 1;
            ch = self.peek(i) catch break;
        }

        return cmd.CmdWordPartStrPart{
            .literal = try self.take(i),
        };
    }

    /// parseStrNonExpandable parses a non-expandable string (e.g. 'foo').
    ///
    /// The cursor will be placed after the string
    /// (e.g. "'foo'" will be returned and the cursor will be at ' ' in "'foo' bar").
    fn parseStrNonExpandable(self: *Self) !*cmd.CmdWordPartStr {
        _ = try self.next();

        const part = try self.allocator.create(cmd.CmdWordPartStr);
        part.* = cmd.CmdWordPartStr.init(self.allocator, false);

        try part.parts.append(try self.parseStringLiteral(isNonExpandableStrLitChar));

        _ = self.next() catch {};

        return part;
    }

    /// parseSub parses a command or process substitution.
    ///
    /// The cursor will be placed after the sub.
    fn parseSub(self: *Self) anyerror!*cmd.Cmd {
        const subPrefix = try self.curr();
        if (!(subPrefix == '$' or subPrefix == '<')) {
            giveup("parseSub: unexpected char in cmd sub: {any}", .{subPrefix});
        }

        const openingBrace = try self.next();
        if (openingBrace != '(') {
            giveup("parseSub: unexpected char in cmd sub: {any}", .{openingBrace});
        }

        // Set up the sub_parser to start on the first character of the subexpr.
        _ = try self.next();

        // Create a new parser that will parse the subexpression using the current buffer position.
        var sub_parser = Self.init(self.allocator, self.buf[self.buf_offset..]);
        sub_parser.in_sub = true;
        const sub = try sub_parser.parse();

        // Skip ahead however many characters the subexpression parsing consumed (+1 for the `)` char).
        _ = try self.take(sub_parser.buf_offset + 1);

        return sub;
    }

    /// parseStrExpandable parses an expandable string (e.g. "foo").
    ///
    /// The cursor will be placed after the string.
    /// (e.g. '"foo$bar"' will be returned and the cursor will be at ' ' in
    /// '"foo$bar" baz').
    fn parseStrExpandable(self: *Self) !*cmd.CmdWordPartStr {
        _ = try self.next();

        const res = try self.allocator.create(cmd.CmdWordPartStr);
        res.* = cmd.CmdWordPartStr.init(self.allocator, true);

        var ch = try self.curr();
        while (true) {
            if (ch == STR_DOUBLE_QUOTE) {
                _ = self.next() catch break;
                break;
            } else if (isExpandableStrLitChar(ch)) {
                try res.parts.append(try self.parseStringLiteral(isExpandableStrLitChar));
            } else if (ch == VAR_EXPAND_START) {
                const part = @unionInit(cmd.CmdWordPartStrPart, "variable", try self.parseVarExpand());
                try res.parts.append(part);
            } else {
                giveup("parseStrExpandable: unexpected char: {any}", .{ch});
            }

            ch = self.curr() catch break;
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
            STR_SINGLE_QUOTE => {
                return self.parseStrNonExpandable();
            },
            STR_DOUBLE_QUOTE => {
                return self.parseStrExpandable();
            },
            else => {
                giveup("parseStr: unexpected char in string: {any}", .{ch});
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

            // If this is the end of the word, we're done!
            if (self.isEndOfWordChar(ch)) {
                return word;
            }

            const part = try self.allocator.create(cmd.CmdWordPart);
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
                else if (ch == STR_SINGLE_QUOTE or ch == STR_DOUBLE_QUOTE) {
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
                    giveup("parseWord: unexpected character: {c}", .{ch});
                }
            };

            try word.parts.append(part);
            ch = self.curr() catch break;
        }

        return word;
    }

    fn isEndOfWordChar(self: Self, ch: u8) bool {
        // If one of the following is true, we're done!
        //  * ch is an "end of word" character
        //  * we're in a substitution and ch is the end of the substitution
        //  * we can currently set vars and ch is an '='
        return (ch == ' ' or ch == '\n' or ch == ';') or (self.in_sub and ch == ')') or (self.can_set_vars and ch == '=');
    }

    /// parse parses the init'd input and returns an executable cmd*.
    pub fn parse(self: *Self) anyerror!*cmd.Cmd {
        self.can_set_vars = true;

        var res = try self.allocator.create(cmd.Cmd);
        res.* = cmd.Cmd.init(self.allocator);

        var ch = try self.curr();
        while (true) {
            ch = self.curr() catch break;

            if (isEndOfLine(ch)) {
                break;
            }

            ch = self.chompWhitespace() catch break;

            if (ch == COMMENT) {
                self.consumeToEndOfLine() catch break;
                break;
            }

            if (self.in_sub and ch == ')') {
                // The end of the sub is also the end of pipeline, but we don't want to flip
                // the `in_sub` bit here; just flip the `in_pipeline` bit and bail; the parser
                // will realize this is the end of the pipeline in the outer scope and bail
                // from _there_ correctly.
                if (self.in_pipeline) {
                    self.in_pipeline = false;
                    return res;
                }

                self.in_sub = false;
                return res;
            }

            if (ch == '\n' or ch == ';') {
                _ = self.next() catch return res;
                return res;
            }

            // Check if this is a literal word.
            if (isLiteralChar(ch) or ch == STR_SINGLE_QUOTE or ch == STR_DOUBLE_QUOTE or ch == VAR_EXPAND_START or ch == '<') {
                const word = try self.parseWord();

                // Check if this is a var assignment.
                if (self.can_set_vars and word.parts.items.len == 1 and self.curr() catch ' ' == '=') {
                    switch (word.parts.items[0].*) {
                        .literal => {
                            _ = try self.next();

                            self.can_set_vars = false;
                            const value = try self.parseWord();
                            self.can_set_vars = true;

                            const var_assignment = try self.allocator.create(cmd.CmdVar);
                            var_assignment.name = word.parts.items[0].literal;
                            var_assignment.value = value;

                            try res.parts.append(.{ .var_assign = var_assignment });
                            continue;
                        },
                        else => {},
                    }
                } else {
                    // Once we're done setting vars, we can no longer set vars.
                    self.can_set_vars = false;
                }

                try res.parts.append(.{ .word = word });
                continue;
            }

            if (ch == '&') {
                // Check if we're in an '&&'.
                ch = try self.peek(1);
                if (ch == '&') {
                    // If we're currently in a pipeline, return the command we've built so far and mark that we've reached the end of the pipeline.
                    if (self.in_pipeline) {
                        self.in_pipeline = false;
                        return res;
                    }

                    self.can_set_vars = true;

                    // Otherwise, chomp the second '&' in '&&' and move to the next character to prepare for the next parse.
                    _ = try self.next();
                    _ = try self.next();

                    // Parse the next command and put it in an "and".
                    try res.parts.append(.{ .and_cmd = try self.parse() });
                    continue;
                } else {
                    giveup("parse: background procs not implemented", .{});
                }
            }

            if (ch == PIPE) {
                self.can_set_vars = true;

                // Look ahead to see if this is a pipe; if it is, then we're about to hit an '||'.
                ch = try self.peek(1);
                if (ch == PIPE) {
                    // If we're currently in a pipeline, return the command we've built so far and mark that we've reached the end of the pipeline.
                    if (self.in_pipeline) {
                        self.in_pipeline = false;
                        return res;
                    }

                    // Otherwise, chomp the second '|' in '||' and move to the next character to prepare for the next parse.
                    _ = try self.next();
                    _ = try self.next();

                    // Parse the next command and put it in an "or".
                    try res.parts.append(.{ .or_cmd = try self.parse() });
                    continue;
                }

                // Move ahead to the next character now that we know we're not in an '||'.
                _ = try self.next();

                // If we're currently in a pipeline, return the command we've built so far so we can add it to the pipeline.
                if (self.in_pipeline) {
                    return res;
                }

                var pipeline = std.ArrayList(*cmd.Cmd).init(self.allocator);

                // Now that we've realized we're for sure in a pipeline, we need to complete the command that's
                // in-progress and add it as the first command in the pipeline.
                //
                // Then, we need to add as many pipeline comands as we can until we find an operation that _isn't_ a pipeline.

                // Complete the first command as the first command in the pipeline.
                try pipeline.append(res);

                // Re-init the current command.
                res = try self.allocator.create(cmd.Cmd);
                res.* = cmd.Cmd.init(self.allocator);

                // Mark that we're currently in a pipeline.
                self.in_pipeline = true;

                // Add as many additional commands as we can.
                while (true) {
                    const next_cmd = self.parse() catch {
                        try res.parts.append(.{ .pipeline = pipeline });
                        break;
                    };

                    // Add the command to the pipeline.
                    try pipeline.append(next_cmd);

                    // If we've exited the pipeline, then we're done!
                    if (!self.in_pipeline) {
                        try res.parts.append(.{ .pipeline = pipeline });

                        break;
                    }
                }

                continue;
            }

            giveup("parse: unexpected char {any}", .{ch});
            unreachable;
        }

        return res;
    }

    fn chompWhitespace(self: *Self) !u8 {
        while (try self.peek(0) == ' ') {
            _ = try self.next();
        }

        return try self.peek(0);
    }

    fn consumeToEndOfLine(self: *Self) !void {
        const ch = try self.curr();
        while (!isEndOfLine(ch)) {
            _ = try self.next();
        }
    }

    fn next(self: *Self) ParseError!u8 {
        const new_offset = self.buf_offset + 1;

        // Always set the offset to the new offset so we can detect if we're at the EOF after this call.
        self.buf_offset = new_offset;

        if (new_offset >= self.buf.len) {
            return ParseError.EOF;
        }

        return self.buf[self.buf_offset];
    }

    /// take consumes n many characters from the input buffer.
    ///
    /// Notes:
    ///   - The result will contain the current character.
    ///   - n will be clamped so that the returned slice never exceeds the length of the buffer.
    fn take(self: *Self, n: usize) ParseError![]u8 {
        var newOffset = self.buf_offset + n;
        if (newOffset >= self.buf.len) {
            newOffset = self.buf.len;
        }

        const result = self.buf[self.buf_offset..newOffset];
        self.buf_offset = newOffset;

        return result;
    }

    fn curr(self: Self) ParseError!u8 {
        return self.peek(0);
    }

    fn peek(self: Self, offset: usize) ParseError!u8 {
        const effectiveOffset = self.buf_offset + offset;

        if (effectiveOffset >= 0 and effectiveOffset < self.buf.len) {
            return self.buf[effectiveOffset];
        } else {
            return ParseError.EOF;
        }
    }
};

pub inline fn isAlpha(ch: u8) bool {
    return (ch >= 'a' and ch <= 'z') or (ch >= 'A' and ch <= 'Z');
}

pub inline fn isNumeric(ch: u8) bool {
    return ch >= 48 and ch <= 57;
}

pub inline fn isLiteralChar(ch: u8) bool {
    return !(ch == ' ' or ch == '\n' or ch == '$' or ch == '`' or ch == '<' or
        ch == '>' or ch == '&' or ch == STR_DOUBLE_QUOTE or ch == STR_SINGLE_QUOTE or
        ch == PIPE or ch == ';');
}

pub inline fn isVarNameChar(ch: u8) bool {
    return isAlpha(ch) or isNumeric(ch) or ch == '_';
}

pub inline fn isEndOfLine(ch: u8) bool {
    return ch == '\n' or ch == 0;
}

pub fn isNonExpandableStrLitChar(ch: u8) bool {
    return ch != STR_SINGLE_QUOTE;
}

// TODO: should `\n` be included; strings can span lines!
pub fn isExpandableStrLitChar(ch: u8) bool {
    return isLiteralChar(ch) or ch == ' ' or ch == ';';
}

pub fn giveup(comptime fmt: []const u8, args: anytype) noreturn {
    std.log.err(fmt, args);
    std.posix.exit(1);
}
