#pragma once

#include "cmd.h"
#include "glib.h"

typedef struct cmd_executor {
  GHashTable *vars;

  int stdin_fno;
  int stdout_fno;
} cmd_executor;

cmd_executor *cmd_executor_new(void);

int cmd_executor_exec(cmd_executor *executor, cmd* cmd);