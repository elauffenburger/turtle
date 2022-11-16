#include "cmd_parser.h";
#include "cmd.h"
#include "glib.h"
#include "utils.h"
#include <stdbool.h>
#include <stdio.h>
#include <unistd.h>

#define UNQUOTED_STR '\''
#define VAR_START '$'

static bool is_alpha(char c) {
  return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z');
}

static bool is_numeric(char c) { return c >= 48 && c <= 57; }

static bool is_reg_char(char c) {
  return is_alpha(c) || is_numeric(c) || c == '-' || c == '_';
}

static bool is_var_char(char c) {
  return is_alpha(c) || is_numeric(c) || c == '_';
}

static void cmd_parser_err(cmd_parser *parser, char *format, ...) {
  va_list args;
  va_start(args, format);

  char full_format[BUFSIZ];
  sprintf(full_format, "parser error: %s\n", format);

  vfprintf(stderr, full_format, args);
  va_end(args);

  exit(1);
}

GString *cmd_parser_parse_word_literal(cmd_parser *parser) {
  GString *literal = NULL;

  while (*parser->next != '\0') {
    char c = *parser->next;

    if (is_reg_char(c)) {
      if (literal == NULL) {
        literal = g_string_new(NULL);
      }

      literal = g_string_append_c(literal, c);
    } else if (c == ' ' || c == '\n') {
      return literal;
    } else {
      cmd_parser_err(parser, "unexpected character %c", c);
      return NULL;
    }

    parser->next++;
  }

  return literal;
}

cmd_word_part_str *cmd_parser_parse_str_literal(cmd_parser *parser) {
  GString *str = g_string_new(NULL);

  while (*parser->next != '\0') {
    char c = *parser->next;

    if (is_reg_char(c) || c == ' ') {
      str = g_string_append_c(str, c);
    } else if (c == UNQUOTED_STR) {
      parser->next++;

      cmd_word_part_str_part *part = malloc(sizeof(cmd_word_part_str_part));
      part->type = CMD_WORD_PART_STR_PART_TYPE_LITERAL;
      part->value.literal = str;

      cmd_word_part_str *res = malloc(sizeof(cmd_word_part_str));
      res->quoted = false;
      res->parts = g_list_alloc();
      res->parts = g_list_append(res->parts, part);

      return res;
    } else {
      cmd_parser_err(parser, "unexpected char: %c", c);
    }

    parser->next++;
  }
}

cmd_word_part_str *cmd_parser_parse_str(cmd_parser *parser) {
  switch (*parser->next) {
  case UNQUOTED_STR: {
    parser->next++;
    return cmd_parser_parse_str_literal(parser);
  }

  default: {
    cmd_parser_err(parser, "unexpected char in string: %c", *parser->next);
  }
  }
}

cmd_word_part_var *cmd_parser_parse_var(cmd_parser *parser) {
  parser->next++;

  cmd_word_part_var *var = malloc(sizeof(cmd_word_part_var));
  var->name = g_string_new(NULL);

  while (*parser->next != 0) {
    char c = *parser->next;

    if (is_var_char(c)) {
      var->name = g_string_append_c(var->name, c);
    } else {
      return var;
    }

    parser->next++;
  }
}

cmd_word *cmd_parser_parse_word(cmd_parser *parser) {
  cmd_word *word = malloc(sizeof(cmd_word));
  word->parts = g_list_alloc();

  while (*parser->next != '\0') {
    char c = *parser->next;

    if (c == ' ' || c == '\n') {
      return word;
    }

    if (is_reg_char(c)) {
      cmd_word_part_value val = {
          .literal = cmd_parser_parse_word_literal(parser),
      };
      cmd_word_part *part = cmd_word_part_new(CMD_WORD_PART_TYPE_LIT, val);

      word->parts = g_list_append(word->parts, part);
    } else if (c == UNQUOTED_STR) {
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
      cmd_parser_err(parser, "unexpected character %c", c);
    }
  }

  return word;
}

cmd_parser *cmd_parser_new() {
  cmd_parser *parser = malloc(sizeof(cmd_parser));

  return parser;
}

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

    if (is_reg_char(c) || c == UNQUOTED_STR || c == VAR_START) {
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

    cmd_parser_err(parser, "unexpected char %c", c);
  }

  return parser->cmd;
}
