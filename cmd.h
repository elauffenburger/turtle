#pragma once

#include "glib.h"
#include <stdbool.h>

typedef struct cmd {
  GList *parts;
} cmd;

typedef struct cmd_parser {
  char *next;

  cmd *cmd;
} cmd_parser;

typedef struct cmd_word {
  // GList<cmd_word_part*>;
  GList *parts;
} cmd_word;

typedef enum cmd_word_part_type {
  CMD_WORD_PART_TYPE_UNK,
  CMD_WORD_PART_TYPE_LIT,
  CMD_WORD_PART_TYPE_STR,
} cmd_word_part_type;

typedef enum cmd_word_part_str_part_type {
  CMD_WORD_PART_STR_PART_TYPE_LITERAL
} cmd_word_part_str_part_type;

typedef struct cmd_word_part_str_part {
  cmd_word_part_str_part_type type;

  union cmd_word_part_str_part_value {
    GString* literal;
  } value;
} cmd_word_part_str_part;

typedef struct cmd_word_part_str {
  bool quoted;
  GList *parts;
} cmd_word_part_str;

typedef struct cmd_word_part {
  cmd_word_part_type type;

  union cmd_word_part_value {
    GString *literal;
    cmd_word_part_str *str;
  } value;
} cmd_word_part;

typedef enum cmd_part_type { CMD_PART_TYPE_WORD } cmd_part_type;

typedef struct cmd_part {
  cmd_part_type type;

  union cmd_part_value {
    cmd_word *word;
  } value;
} cmd_part;

cmd_parser *cmd_parser_new(void);

cmd *cmd_parser_parse(cmd_parser *parser, char *input);

void cmd_exec(cmd *cmd);