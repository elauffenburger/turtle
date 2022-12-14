#include "cmd_executor.h"
#include "glib.h"

GString *cmd_executor_get_var(cmd_executor *executor, char *name) {
  // Check if this is a special var name.
  if (strncmp(name, "!", 1) == 0) {
    GString *result = g_string_new(NULL);
    g_string_printf(result, "%d", executor->last_pid);
    return result;
  }

  // Check if we have a var def for the command.
  char *value = g_hash_table_lookup(executor->vars, name);
  if (value == NULL) {
    // Fallback to the environment.
    value = getenv(name);
  }

  if (value == NULL) {
    return NULL;
  }

  GString *result = g_string_new(NULL);
  g_string_printf(result, "%s", value);
  return result;
}

void set_var(GHashTable *vars, char *name, char *value) {
  // Copy the name and value so they don't reference memory owned by the
  // cmd (which will be freed later).
  char *name_cpy = malloc((strlen(name) + 1) * sizeof(char));
  char *value_cpy = malloc((strlen(value) + 1) * sizeof(char));
  strcpy(name_cpy, name);
  strcpy(value_cpy, value);

  g_hash_table_insert(vars, name_cpy, value_cpy);
}