#pragma once

#include "cmd_executor.h"
#include "glib.h"

GString *cmd_executor_get_var(cmd_executor *executor, char *name);

void set_var(GHashTable *vars, char *name, char *value);