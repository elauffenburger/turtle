#include "cmd.h"
#include "glib.h"
#include "utils.h"
#include <stdbool.h>
#include <stdio.h>
#include <unistd.h>

#define UNQUOTED_STR '\''

static bool is_alpha(char c) {
  return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z');
}

static bool is_numeric(char c) { return c >= 48 && c <= 57; }

static bool is_reg_char(char c) {
  return is_alpha(c) || is_numeric(c) || c == '-';
}

void cmd_parser_err(cmd_parser *parser, char *format, ...) {
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

cmd_word *cmd_parser_parse_word(cmd_parser *parser) {
  cmd_word *word = malloc(sizeof(cmd_word));
  word->parts = g_list_alloc();

  while (*parser->next != '\0') {
    char c = *parser->next;

    if (c == ' ' || c == '\n') {
      return word;
    }

    if (is_reg_char(c)) {
      GString *literal = cmd_parser_parse_word_literal(parser);

      cmd_word_part *part = malloc(sizeof(cmd_word_part));
      part->type = CMD_WORD_PART_TYPE_LIT;
      part->value.literal = literal;

      word->parts = g_list_append(word->parts, part);
    } else if (c == UNQUOTED_STR) {
      cmd_word_part_str *str = cmd_parser_parse_str(parser);

      cmd_word_part *part = malloc(sizeof(cmd_word_part));
      part->type = CMD_WORD_PART_TYPE_STR;
      part->value.str = str;

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

cmd *cmd_new(void) {
  cmd *cmd = malloc(sizeof(cmd));
  cmd->parts = g_list_alloc();

  return cmd;
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

    if (is_reg_char(c) || c == UNQUOTED_STR) {
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

char *cmd_word_to_str(cmd_word *word) {
  GString *res = g_string_new(NULL);

  for (GList *node = word->parts->next; node != NULL; node = node->next) {
    cmd_word_part *part = (cmd_word_part *)node->data;

    switch (part->type) {
    case CMD_WORD_PART_TYPE_LIT: {
      res = g_string_append(res, part->value.literal->str);
      break;
    }

    case CMD_WORD_PART_TYPE_STR: {
      cmd_word_part_str *str = part->value.str;
      if (str->quoted) {
        giveup("quoted strings not implemented");
      } else {
        for (GList *str_node = str->parts->next; str_node != NULL;
             str_node = str_node->next) {
          cmd_word_part_str_part *str_part = str_node->data;

          switch (str_part->type) {
          case CMD_WORD_PART_STR_PART_TYPE_LITERAL: {
            res = g_string_append(res, str_part->value.literal->str);
            break;
          }
          default:
            giveup("str part type not implemented");
          }
        }
      }

      break;
    }

    default:
      giveup("unimplemented cmd_word_part_type");
    }
  }

  return res->str;
}

void cmd_exec(cmd *cmd) {
  char *file = NULL;

  int argc = 1;
  GList *gargs = g_list_alloc();

  for (GList *node = cmd->parts->next; node != NULL; node = node->next) {
    cmd_part *part = (cmd_part *)node->data;

    switch (part->type) {
    case CMD_PART_TYPE_WORD: {
      char *word = cmd_word_to_str(part->value.word);
      if (file == NULL) {
        file = word;
        gargs = g_list_append(gargs, file);
      } else {
        argc++;

        gargs = g_list_append(gargs, word);
      }

      break;
    }
    default:
      giveup("not implemented");
    }
  }

  char *argv[argc + 1];
  {
    int i = 0;
    for (GList *node = gargs->next; node != NULL; node = node->next) {
      argv[i] = (char *)node->data;
      i++;
    }

    argv[i] = NULL;
  }

  pid_t pid;
  if ((pid = fork()) == 0) {
    execvp(file, argv);
    giveup("exec failed");
    exit(1);
  }

  int status;
  if ((pid = waitpid(pid, &status, 0)) < 0) {
    giveup("child process failed");
  }
}