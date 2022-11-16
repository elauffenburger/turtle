#pragma once

#include "glib.h"
#include <stdbool.h>

typedef struct cmd {
  GList *parts;
} cmd;

typedef struct cmd_word {
  // GList<cmd_word_part*>;
  GList *parts;
} cmd_word;

typedef enum cmd_word_part_type {
  CMD_WORD_PART_TYPE_UNK,
  CMD_WORD_PART_TYPE_LIT,
  CMD_WORD_PART_TYPE_STR,
  CMD_WORD_PART_TYPE_VAR,
} cmd_word_part_type;

typedef struct cmd_word_part_var {
  GString *name;
} cmd_word_part_var;

typedef enum cmd_word_part_str_part_type {
  CMD_WORD_PART_STR_PART_TYPE_LITERAL,
  CMD_WORD_PART_STR_PART_TYPE_VAR,
} cmd_word_part_str_part_type;

typedef struct cmd_word_part_str_part {
  cmd_word_part_str_part_type type;

  union cmd_word_part_str_part_value {
    GString *literal;
    cmd_word_part_var *var;
  } value;
} cmd_word_part_str_part;

typedef struct cmd_word_part_str {
  bool quoted;
  GList *parts;
} cmd_word_part_str;

typedef union cmd_word_part_value {
  GString *literal;
  cmd_word_part_str *str;
  cmd_word_part_var *var;
} cmd_word_part_value;

typedef struct cmd_word_part {
  cmd_word_part_type type;

  cmd_word_part_value value;
} cmd_word_part;

typedef enum cmd_part_type { CMD_PART_TYPE_WORD } cmd_part_type;

typedef struct cmd_part {
  cmd_part_type type;

  union cmd_part_value {
    cmd_word *word;
  } value;
} cmd_part;

void cmd_exec(cmd *cmd);

cmd_word_part *cmd_word_part_new(cmd_word_part_type type,
                                 cmd_word_part_value val);

cmd *cmd_new(void);