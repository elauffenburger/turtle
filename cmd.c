#include "cmd.h"
#include "glib.h"
#include "utils.h"
#include <stdbool.h>
#include <stdio.h>

static bool is_alpha(char c) {
  int i = (int)c;
  return (i >= 65 && i <= 90) || (i >= 97 && i <= 122);
}

static bool is_numeric(char c) { return c >= 48 && c <= 57; }

cmd_word *cmd_parser_parse_word(cmd_parser *parser) {
  cmd_word *word = malloc(sizeof(cmd_word));

  GString *literal = NULL;

  while (*parser->next != '\0') {
    char c = *parser->next;

    if (is_alpha(c) || is_numeric(c)) {
      if (literal == NULL) {
        literal = g_string_new(NULL);
      }

      literal = g_string_append_c(literal, c);
    } else if (c == ' ' || c == '\n') {
      if (literal != NULL) {
        parser->next++;

        cmd_word_part *part = malloc(sizeof(cmd_word_part));
        part->type = CMD_WORD_PART_TYPE_LIT;
        part->value.literal = literal;

        word->parts = g_list_append(word->parts, part);

        return word;
      }
    } else {
      parser->err = sprintf("unexpected character %c", c);
      return NULL;
    }

    parser->next++;
  }

  return word;
}

cmd_parser *cmd_parser_new() {
  cmd_parser *parser = malloc(sizeof(cmd_parser));

  return parser;
}

cmd *cmd_parser_parse(cmd_parser *parser, char *input) {
  parser->cmd = malloc(sizeof(cmd));
  parser->next = input;
  parser->err = NULL;

  while (*parser->next != '\0') {
    if (parser->err != NULL) {
      return NULL;
    }

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

    parser->err = sprintf("unexpected char %c", c);
    return NULL;
  }

  return parser->cmd;
}

void cmd_exec(cmd *cmd) {
  char* file = NULL;
  GList* args;

  for (GList *node = cmd->parts->next; node != NULL; node = node->next) {
    cmd_part *part = (cmd_part *)node->data;

    switch (part->type) {
    case CMD_PART_TYPE_WORD: {
      if(file == NULL) {

      }

      break;
    }
    default:
      giveup("not implemented");
    }
  }
}