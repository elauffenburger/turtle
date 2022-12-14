#include "cmd_parser.h"
#include "cmd.h"
#include "glib.h"
#include "utils.h"
#include <stdbool.h>
#include <stdio.h>
#include <unistd.h>

#define STR_UNQUOTED '\''
#define STR_QUOTED '"'
#define VAR_EXPAND_START '$'
#define VAR_ASSIGN '='
#define PIPE '|'
#define COMMENT '#'

static bool is_alpha(char c) {
  return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z');
}

static bool is_numeric(char c) { return c >= 48 && c <= 57; }

static bool is_literal_char(char c) {
  return !(c == ' ' || c == '\n' || c == '$' || c == '`' || c == '<' ||
           c == '>' || c == '&' || c == STR_QUOTED || c == STR_UNQUOTED ||
           c == PIPE || c == ';');
}

static bool is_var_name_char(char c) {
  return is_alpha(c) || is_numeric(c) || c == '_';
}

static bool is_end_of_line(char c) { return c == '\n' || c == '\0'; }

static inline void parser_consume_to_end_of_line(cmd_parser *parser) {
  while (!is_end_of_line(*parser->next)) {
    parser->next++;
  }
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

// cmd_parser_parse_var_expand parses a variable expansion.
//
// The cursor will be placed after the var name.
// (e.g. "$var" will be returned and the cursor will be at "/" in "$var/baz").
cmd_word_part_var *cmd_parser_parse_var_expand(cmd_parser *parser) {
  parser->next++;
  char c = *parser->next;

  cmd_word_part_var *var = malloc(sizeof(cmd_word_part_var));
  var->name = g_string_new(NULL);

  // Check for special var names.
  if (c == '!' || c == '?') {
    var->name = g_string_append_c(var->name, c);
    parser->next++;
    return var;
  }

  while (c != 0) {
    c = *parser->next;

    if (!is_var_name_char(c)) {
      break;
    }

    var->name = g_string_append_c(var->name, c);
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

    if (parser->in_sub && c == ')') {
      return literal;
    }

    if (is_literal_char(c)) {
      if (literal == NULL) {
        literal = g_string_new(NULL);
      }

      literal = g_string_append_c(literal, c);
    } else if (c == ' ' || c == '\n') {
      return literal;
    } else if (c == ';') {
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
  res->parts = g_list_append(
      NULL, cmd_parser_parse_str_literal(parser, is_str_unquoted_lit_char));

  parser->next++;

  return res;
}

static bool is_str_quoted_lit_char(char c) {
  return is_literal_char(c) || c == ' ' || c == ';';
}

// cmd_parser_parse_sub parses a command or process substitution.
//
// The cursor will be placed after the sub.
cmd *cmd_parser_parse_sub(cmd_parser *parser) {
  if (!(*parser->next == '$' || *parser->next == '<') ||
      *(parser->next + 1) != '(') {
    cmd_parser_err(parser, "unexpected char in cmd sub: %s", parser->next);
  }

  parser->next += 2;

  bool was_in_sub = parser->in_sub;
  parser->in_sub = true;
  cmd *cmd = cmd_parser_parse(parser, parser->next);
  parser->in_sub = was_in_sub;

  return cmd;
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
  res->parts = NULL;

  while (*parser->next != '\0') {
    char c = *parser->next;

    if (is_str_quoted_lit_char(c)) {
      cmd_word_part_str_part *part =
          cmd_parser_parse_str_literal(parser, is_str_quoted_lit_char);

      res->parts = g_list_append(res->parts, part);
    } else if (c == VAR_EXPAND_START) {
      cmd_word_part_var *var = cmd_parser_parse_var_expand(parser);

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
  word->parts = NULL;

  while (*parser->next != '\0') {
    char c = *parser->next;

    if (c == COMMENT) {
      parser_consume_to_end_of_line(parser);
      return word;
    }

    if (c == ' ' || c == '\n' || c == ';' || (parser->in_sub && c == ')')) {
      return word;
    }

    // Check if this is a command sub.
    if (c == VAR_EXPAND_START && *(parser->next + 1) == '(') {
      cmd_word_part_value val = {
          .cmd_sub = cmd_parser_parse_sub(parser),
      };
      cmd_word_part *part = cmd_word_part_new(CMD_WORD_PART_TYPE_CMD_SUB, val);

      word->parts = g_list_append(word->parts, part);

      continue;
    }

    // Check if this is a proc sub.
    if (c == '<' && *(parser->next + 1) == '(') {
      cmd_word_part_value val = {
          .proc_sub = cmd_parser_parse_sub(parser),
      };
      cmd_word_part *part = cmd_word_part_new(CMD_WORD_PART_TYPE_PROC_SUB, val);

      word->parts = g_list_append(word->parts, part);

      continue;
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
    } else if (c == VAR_EXPAND_START) {
      cmd_word_part_value val = {
          .var = cmd_parser_parse_var_expand(parser),
      };
      cmd_word_part *part = cmd_word_part_new(CMD_WORD_PART_TYPE_VAR, val);

      word->parts = g_list_append(word->parts, part);
    } else {
      cmd_parser_err(parser, "parse_word: unexpected character %c", c);
    }
  }

  return word;
}

cmd_parser *cmd_parser_new(void) {
  cmd_parser *parser = malloc(sizeof(cmd_parser));
  parser->in_sub = false;

  return parser;
}

void cmd_parser_set_next(cmd_parser *parser, char *next) {
  parser->in_sub = false;
  parser->next = next;
}

// cmd_parser_parse parses the provided input and returns an executable cmd*.
cmd *cmd_parser_parse(cmd_parser *parser, char *input) {
  if (input == NULL || *input == 0) {
    return NULL;
  }

  cmd *res = cmd_new();

  parser->next = input;

  bool can_set_vars = true;
  while (*parser->next != '\0') {
    char c = *parser->next;

    while (c == ' ') {
      c = *++parser->next;
    }

    if (c == COMMENT) {
      parser_consume_to_end_of_line(parser);
      return res;
    }

    if (c == '\n' || c == ';' || (parser->in_sub && c == ')')) {
      parser->next++;
      return res;
    }

    // Check if this is a var assignment.
    if (can_set_vars && is_literal_char(c)) {
      // Peek to the ' '
      char *space_ch = strstr(parser->next, " ");

      // If that failed, try '\n'
      if (space_ch == NULL) {
        space_ch = strstr(parser->next, "\n");
      }

      // If that failed, try NULL
      if (space_ch == NULL) {
        space_ch = strstr(parser->next, "\0");
      }

      if (space_ch != NULL) {
        size_t space_index = (size_t)(space_ch - parser->next);

        // Peek to the '='.
        char *var_assign_ch = strnstr(parser->next, "=", space_index - 1);
        if (var_assign_ch != NULL) {
          size_t var_assign_index = (size_t)(var_assign_ch - parser->next);

          // Grab the name.
          char *name = malloc((var_assign_index + 1) * sizeof(char));
          memcpy(name, parser->next, var_assign_index);
          name[var_assign_index] = 0;

          // Read the value as the next word on the other side of the '='.
          parser->next = var_assign_ch + 1;
          cmd_word *value = cmd_parser_parse_word(parser);

          cmd_var_assign *var = malloc(sizeof(cmd_var_assign));
          var->name = name;
          var->value = value;

          cmd_part *part = malloc(sizeof(cmd_part));
          part->type = CMD_PART_TYPE_VAR_ASSIGN;
          part->value.var_assign = var;

          res->parts = g_list_append(res->parts, part);

          continue;
        }
      }
    }

    // Check if this is a word.
    if (is_literal_char(c) || c == STR_UNQUOTED || c == STR_QUOTED ||
        c == VAR_EXPAND_START || c == '<') {
      can_set_vars = false;

      cmd_part *part = malloc(sizeof(cmd_part));
      part->type = CMD_PART_TYPE_WORD;
      part->value.word = cmd_parser_parse_word(parser);

      res->parts = g_list_append(res->parts, part);
      continue;
    }

    // Check if this is a background proc or an AND.
    if (c == '&') {
      parser->next++;

      if (*parser->next == '&') {
        can_set_vars = true;

        parser->next++;

        // Read everything to the right of the AND as its own cmd.
        cmd *and_cmd = cmd_parser_parse(parser, parser->next);

        cmd_part *part = malloc(sizeof(cmd_part));
        part->type = CMD_PART_TYPE_AND;
        part->value.and_cmd = and_cmd;

        res->parts = g_list_append(res->parts, part);
      } else {
        giveup("parse: background procs not implemented");
      }

      continue;
    }

    // Check if this is a pipe or an OR.
    if (c == PIPE) {
      can_set_vars = true;

      parser->next++;

      if (*parser->next == '|') {
        parser->next++;

        // Read everything to the right of the OR as its own cmd.
        cmd *or_cmd = cmd_parser_parse(parser, parser->next);

        cmd_part *part = malloc(sizeof(cmd_part));
        part->type = CMD_PART_TYPE_OR;
        part->value.or_cmd = or_cmd;

        res->parts = g_list_append(res->parts, part);
      } else {
        // Read everything to the right of the pipe as its own cmd.
        cmd *piped_cmd = cmd_parser_parse(parser, parser->next);

        cmd_part *part = malloc(sizeof(cmd_part));
        part->type = CMD_PART_TYPE_PIPE;
        part->value.piped_cmd = piped_cmd;

        res->parts = g_list_append(res->parts, part);
      }

      continue;
    }

    cmd_parser_err(parser, "parse: unexpected char %c", c);
  }

  return res;
}

cmd *cmd_parser_parse_next(cmd_parser *parser) {
  return cmd_parser_parse(parser, parser->next);
}