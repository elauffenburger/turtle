#pragma once

#include "glib.h"

typedef enum cmd_type { CMD_TYPE_PROC_SUB, CMD_TYPE_LIT } cmd_type;

typedef struct cmd_proc_sub {

} cmd_proc_sub;

typedef struct cmd_lit {
  char *prog;

  GList *gargs;
} cmd_lit;

typedef struct cmd {
  cmd_type type;
  char *err;

  union cmd_value {
    cmd_proc_sub proc_sub;
    cmd_lit lit;
  } value;
} cmd;

int cmd_lit_argc(cmd_lit *cmd);

void cmd_lit_argv(cmd_lit *cmd, char **args);

cmd *cmd_parse_line(char *input);