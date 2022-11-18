#pragma once

#include "cmd.h"
#include "glib.h"

typedef struct cmd_executor {
  GHashTable *vars;
} cmd_executor;

cmd_executor *cmd_executor_new(void);

void cmd_executor_exec(cmd_executor *executor, cmd* cmd);