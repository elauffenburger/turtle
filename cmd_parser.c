#include "cmd_parser.h"
#include "cmd.h"
#include "glib.h"
#include "utils.h"
#include <stdbool.h>
#include <stdio.h>
#include <unistd.h>

#define STR_UNQUOTED '\''
#define STR_QUOTED '"'
#define VAR_START '$'

static bool is_alpha(char c) {
  return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z');
}

static bool is_numeric(char c) { return c >= 48 && c <= 57; }

static bool is_literal_char(char c) {
  return !(c == ' ' || c == '\n' || c == '$' || c == '`' || c == '<' ||
           c == '>' || c == '&' || c == STR_QUOTED || c == STR_UNQUOTED);
}

static bool is_var_name_char(char c) {
  return is_alpha(c) || is_numeric(c) || c == '_';
}

#pragma clang diagnostic ignored "-Wunused-parameter"
#pragma clang diagnostic push
static void cmd_parser_err(cmd_parser *parser, char *fmt, ...) {
  va_list args;
  va_start(args, fmt);

  char full_format[BUFSIZ];
  snprintf(full_format, BUFSIZ, "parser error: %s\n", fmt);

  vfprintf(stderr, full_format, args);
  va_end(args);

  exit(1);
}
#pragma clang diagnostic pop

// cmd_parser_parse_var parses a variable.
//
// The cursor will be placed after the var name.
// (e.g. "$var" will be returned and the cursor will be at "/" in "$var/baz").
cmd_word_part_var *cmd_parser_parse_var(cmd_parser *parser) {
  parser->next++;

  cmd_word_part_var *var = malloc(sizeof(cmd_word_part_var));
  var->name = g_string_new(NULL);

  while (*parser->next != 0) {
    char c = *parser->next;

    if (is_var_name_char(c)) {
      var->name = g_string_append_c(var->name, c);
    } else {
      break;
    }

    parser->next++;
  }

  return var;
}

// cmd_parser_parse_word_literal parses a word literal.
//
// The cursor will be placed after at the last character of the literal
// (e.g. "foo" will be returned and cursor will be at ' ' in "foo bar").
GString *cmd_parser_parse_word_literal(cmd_parser *parser) {
  GString *literal = NULL;

  while (*parser->next != '\0') {
    char c = *parser->next;

    if (is_literal_char(c)) {
      if (literal == NULL) {
        literal = g_string_new(NULL);
      }

      literal = g_string_append_c(literal, c);
    } else if (c == ' ' || c == '\n') {
      return literal;
    } else {
      cmd_parser_err(parser, "word_literal: unexpected character %c", c);
      return NULL;
    }

    parser->next++;
  }

  return literal;
}

// cmd_parser_parse_str_literal parses a string literal.
//
// The cursor will be placed at the end of the literal
// (e.g. "foo" will be returned and the cursor will be at '$' in "foo$bar").
cmd_word_part_str_part *cmd_parser_parse_str_literal(cmd_parser *parser,
                                                     bool (*predicate)(char)) {
  cmd_word_part_str_part *part = malloc(sizeof(cmd_word_part_str_part));
  part->type = CMD_WORD_PART_STR_PART_TYPE_LITERAL;
  part->value.literal = g_string_new(NULL);

  while (*parser->next != '\0') {
    char c = *parser->next;

    if (predicate(c)) {
      part->value.literal = g_string_append_c(part->value.literal, c);
    } else {
      break;
    }

    parser->next++;
  }

  return part;
}

static bool is_str_unquoted_lit_char(char c) { return c != STR_UNQUOTED; }

// cmd_parser_parse_str_unquoted parses an unquoted string.
//
// The cursor will be placed after the string
// (e.g. "'foo'" will be returned and the cursor will be at ' ' in "'foo' bar").
cmd_word_part_str *cmd_parser_parse_str_unquoted(cmd_parser *parser) {
  parser->next++;

  cmd_word_part_str *res = malloc(sizeof(cmd_word_part_str));
  res->quoted = false;
  res->parts = g_list_alloc();
  res->parts = g_list_append(res->parts, cmd_parser_parse_str_literal(
                                             parser, is_str_unquoted_lit_char));

  parser->next++;

  return res;
}

static bool is_str_quoted_lit_char(char c) {
  return is_literal_char(c) || c == ' ';
}

// cmd_parser_parse_str_quoted parses a quoted string.
//
// The cursor will be placed after the string.
// (e.g. '"foo$bar"' will be returned and the cursor will be at ' ' in
// '"foo$bar" baz').
cmd_word_part_str *cmd_parser_parse_str_quoted(cmd_parser *parser) {
  parser->next++;

  cmd_word_part_str *res = malloc(sizeof(cmd_word_part_str));
  res->quoted = true;
  res->parts = g_list_alloc();

  while (*parser->next != '\0') {
    char c = *parser->next;

    if (is_str_quoted_lit_char(c)) {
      cmd_word_part_str_part *part =
          cmd_parser_parse_str_literal(parser, is_str_quoted_lit_char);

      res->parts = g_list_append(res->parts, part);
    } else if (c == VAR_START) {
      cmd_word_part_var *var = cmd_parser_parse_var(parser);

      cmd_word_part_str_part *part = malloc(sizeof(cmd_word_part_str_part));
      part->type = CMD_WORD_PART_STR_PART_TYPE_VAR;
      part->value.var = var;

      res->parts = g_list_append(res->parts, part);
    } else if (c == STR_QUOTED) {
      parser->next++;

      break;
    } else {
      cmd_parser_err(parser, "str_quoted: unexpected char: %c", c);
    }
  }

  return res;
}

// cmd_parser_parse_str parses a string.
//
// The cursor will be placed after the string.
// (e.g. "'foo'" will be returned and the cursor will be at ' ' in "'foo' bar").
cmd_word_part_str *cmd_parser_parse_str(cmd_parser *parser) {
  switch (*parser->next) {
  case STR_UNQUOTED: {
    return cmd_parser_parse_str_unquoted(parser);
  }

  case STR_QUOTED: {
    return cmd_parser_parse_str_quoted(parser);
  }

  default: {
    cmd_parser_err(parser, "parse_str: unexpected char in string: %c",
                   *parser->next);
  }
  }

  return NULL;
}

// cmd_parser_parse_word parses a word.
//
// The cursor will be placed after the word.
// (e.g. "foo" will be returned and the cursor will be at ' ' in "foo bar").
cmd_word *cmd_parser_parse_word(cmd_parser *parser) {
  cmd_word *word = malloc(sizeof(cmd_word));
  word->parts = g_list_alloc();

  while (*parser->next != '\0') {
    char c = *parser->next;

    if (c == ' ' || c == '\n') {
      return word;
    }

    if (is_literal_char(c)) {
      cmd_word_part_value val = {
          .literal = cmd_parser_parse_word_literal(parser),
      };
      cmd_word_part *part = cmd_word_part_new(CMD_WORD_PART_TYPE_LIT, val);

      word->parts = g_list_append(word->parts, part);
    } else if (c == STR_UNQUOTED || c == STR_QUOTED) {
      cmd_word_part_value val = {
          .str = cmd_parser_parse_str(parser),
      };
      cmd_word_part *part = cmd_word_part_new(CMD_WORD_PART_TYPE_STR, val);

      word->parts = g_list_append(word->parts, part);
    } else if (c == VAR_START) {
      cmd_word_part_value val = {
          .var = cmd_parser_parse_var(parser),
      };
      cmd_word_part *part = cmd_word_part_new(CMD_WORD_PART_TYPE_VAR, val);

      word->parts = g_list_append(word->parts, part);
    } else {
      cmd_parser_err(parser, "parse_word: unexpected character %c", c);
    }
  }

  return word;
}

cmd_parser *cmd_parser_new() {
  cmd_parser *parser = malloc(sizeof(cmd_parser));

  return parser;
}

// cmd_parser_parse parses the provided input and returns an executable cmd*.
cmd *cmd_parser_parse(cmd_parser *parser, char *input) {
  parser->cmd = cmd_new();

  parser->next = input;

  while (*parser->next != '\0') {
    char c = *parser->next;

    while (c == ' ') {
      c = *++parser->next;
    }

    if (c == '\n') {
      parser->next++;
      return parser->cmd;
    }

    if (is_literal_char(c) || c == STR_UNQUOTED || c == STR_QUOTED ||
        c == VAR_START) {
      cmd_word *word;
      if ((word = cmd_parser_parse_word(parser)) == NULL) {
        return NULL;
      }

      cmd_part *part = malloc(sizeof(cmd_part));
      part->type = CMD_PART_TYPE_WORD;
      part->value.word = word;

      parser->cmd->parts = g_list_append(parser->cmd->parts, part);

      continue;
    }

    cmd_parser_err(parser, "parse: unexpected char %c", c);
  }

  return parser->cmd;
}
