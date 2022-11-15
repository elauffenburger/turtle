#pragma once

#include "glib.h"

typedef enum cmd_part_type {
  CMD_PART_TYPE_PROC_SUB,
  CMD_PART_TYPE_WORD
} cmd_part_type;

struct cmd;

typedef struct cmd_part_proc_sub {
} cmd_part_proc_sub;

typedef struct cmd_part_word {
  char *prog;
} cmd_part_word;

typedef struct cmd_part {
  cmd_part_type type;

  union cmd_part_value {
    cmd_part_proc_sub* proc_sub;
    cmd_part_word* word;
  } value;
} cmd_part;

typedef struct cmd {
  GList *parts;
} cmd;

typedef struct cmd_parser {
  char *next;

  cmd *cmd;

  char *err;
} cmd_parser;

typedef struct cmd_word {
  GList *parts;
} cmd_word;

typedef enum cmd_word_part_type { CMD_WORD_PART_TYPE_LIT } cmd_word_part_type;

typedef struct cmd_word_part {
  cmd_word_part_type type;

  union cmd_word_part_value {
    GString *literal;
  } value;
} cmd_word_part;

cmd_parser *cmd_parser_new();

cmd *cmd_parser_parse(cmd_parser *parser, char* input);

void cmd_exec(cmd *cmd);