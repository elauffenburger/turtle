#pragma once

#include "../cmd.h"
#include "glib.h"
#include <setjmp.h>

typedef struct cmd_executor {
  GHashTable *vars;

  int stdin_fno;
  int stdout_fno;

  pid_t pg_id;
  pid_t last_pid;

  jmp_buf err_jmp;
} cmd_executor;

cmd_executor *cmd_executor_new(void);

int cmd_executor_exec(cmd_executor *executor, cmd *cmd);