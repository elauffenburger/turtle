#include "cmd.h"
#include "glib.h"
#include "utils.h"
#include <stdbool.h>
#include <stdio.h>
#include <unistd.h>

static bool is_alpha(char c) {
  int i = (int)c;
  return (i >= 65 && i <= 90) || (i >= 97 && i <= 122);
}

static bool is_numeric(char c) { return c >= 48 && c <= 57; }

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

    if (is_alpha(c) || is_numeric(c)) {
      if (literal == NULL) {
        literal = g_string_new(NULL);
      }

      literal = g_string_append_c(literal, c);
    } else if (c == ' ' || c == '\n') {
      parser->next++;

      return literal;
    } else {
      cmd_parser_err(parser, "unexpected character %c", c);
      return NULL;
    }

    parser->next++;
  }

  return literal;
}

cmd_word *cmd_parser_parse_word(cmd_parser *parser) {
  cmd_word *word = malloc(sizeof(cmd_word));
  word->parts = g_list_alloc();

  cmd_word_part_type type = CMD_WORD_PART_TYPE_UNK;
  GString *literal = NULL;

  while (*parser->next != '\0') {
    char c = *parser->next;

    if (is_alpha(c) || is_numeric(c)) {
      GString *literal = cmd_parser_parse_word_literal(parser);

      cmd_word_part *part = malloc(sizeof(cmd_word_part));
      part->type = CMD_WORD_PART_TYPE_LIT;
      part->value.literal = literal;

      word->parts = g_list_append(word->parts, part);

      return word;
    } else {
      cmd_parser_err(parser, "unexpected character %c", c);
    }

    parser->next++;
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
      parser->next++;
    }

    if (is_alpha(c) || is_numeric(c)) {
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
  GString *str = g_string_new(NULL);

  for (GList *node = word->parts->next; node != NULL; node = node->next) {
    cmd_word_part *part = (cmd_word_part *)node->data;

    switch (part->type) {
    case CMD_WORD_PART_TYPE_LIT:
      str = g_string_append(str, part->value.literal->str);
      break;
    }
  }

  return str->str;
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