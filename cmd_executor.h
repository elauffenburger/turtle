#pragma once

#include "cmd.h"
#include "glib.h"

typedef struct cmd_executor {
  GHashTable *vars;
} cmd_executor;

cmd_executor *cmd_executor_new(void);

char *cmd_executor_word_to_str(cmd_executor *executor, cmd_word *word);

int cmd_executor_exec(cmd_executor *executor, char *file, char **argv);