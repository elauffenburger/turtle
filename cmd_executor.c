#include "cmd_executor.h"
#include "cmd.h"
#include "utils.h"
#include <unistd.h>

char *cmd_executor_word_to_str(cmd_executor *executor, cmd_word *word);

cmd_executor *cmd_executor_new() {
  cmd_executor *executor = malloc(sizeof(cmd_executor));
  executor->vars = g_hash_table_new(g_str_hash, g_str_equal);

  return executor;
}

char *cmd_executor_get_var(cmd_executor *executor, cmd_word_part_var *var) {
  // Check if we have a var def.
  char *var_val = g_hash_table_lookup(executor->vars, var->name->str);
  if (var_val != NULL) {
    return var_val;
  }

  // If not, fallback to the environment.
  return getenv(var->name->str);
}

void cmd_executor_set_var(cmd_executor *executor, cmd_var_assign *var) {
  char *value = cmd_executor_word_to_str(executor, var->value);
  g_hash_table_insert(executor->vars, var->name, value);
}

char *cmd_executor_word_to_str(cmd_executor *executor, cmd_word *word) {
  GString *res = g_string_new(NULL);

  for (GList *node = word->parts->next; node != NULL; node = node->next) {
    cmd_word_part *part = (cmd_word_part *)node->data;

    switch (part->type) {
    case CMD_WORD_PART_TYPE_LIT: {
      res = g_string_append(res, part->value.literal->str);
      break;
    }

    case CMD_WORD_PART_TYPE_STR: {
      cmd_word_part_str *str = part->value.str;
      if (str->quoted) {
        for (GList *str_node = str->parts->next; str_node != NULL;
             str_node = str_node->next) {
          cmd_word_part_str_part *str_part = str_node->data;

          switch (str_part->type) {
          case CMD_WORD_PART_STR_PART_TYPE_LITERAL: {
            res = g_string_append(res, str_part->value.literal->str);
            break;
          }

          case CMD_WORD_PART_STR_PART_TYPE_VAR: {
            char *val = cmd_executor_get_var(executor, str_part->value.var);
            if (val != NULL) {
              res = g_string_append(res, val);
            }

            break;
          }

          default:
            giveup("str part type not implemented");
          }
        }
      } else {
        for (GList *str_node = str->parts->next; str_node != NULL;
             str_node = str_node->next) {
          cmd_word_part_str_part *str_part = str_node->data;

          switch (str_part->type) {
          case CMD_WORD_PART_STR_PART_TYPE_LITERAL: {
            res = g_string_append(res, str_part->value.literal->str);
            break;
          }

          case CMD_WORD_PART_STR_PART_TYPE_VAR:
            giveup("cmd_executor_word_to_str: unexpected var");

          default:
            giveup("str part type not implemented");
          }
        }
      }

      break;
    }

    case CMD_WORD_PART_TYPE_VAR: {
      char *val = cmd_executor_get_var(executor, part->value.var);
      if (val != NULL) {
        res = g_string_append(res, val);
      }

      break;
    }

    default:
      giveup("unimplemented cmd_word_part_type");
    }
  }

  return res->str;
}

#pragma clang diagnostic ignored "-Wunused-parameter"
#pragma clang diagnostic push
int cmd_executor_fork_exec(cmd_executor *executor, char *file, char **argv) {
  pid_t pid;
  if ((pid = fork()) == 0) {
    execvp(file, argv);
    giveup("exec failed");
    exit(1);
  }

  int status;
  if ((pid = waitpid(pid, &status, 0)) < 0) {
    // TODO: ...something??
  }

  return status;
}
#pragma clang diagnostic pop

void cmd_executor_exec(cmd_executor *executor, cmd *cmd) {
  char *file = NULL;

  int argc = 0;
  GList *gargs = g_list_alloc();

  for (GList *node = cmd->parts->next; node != NULL; node = node->next) {
    cmd_part *part = (cmd_part *)node->data;

    switch (part->type) {
    case CMD_PART_TYPE_WORD: {
      char *word = cmd_executor_word_to_str(executor, part->value.word);
      if (file == NULL) {
        argc++;

        file = word;
        gargs = g_list_append(gargs, file);
      } else {
        argc++;

        gargs = g_list_append(gargs, word);
      }

      break;
    }

    case CMD_PART_TYPE_VAR_ASSIGN: {
      cmd_var_assign *var = part->value.var_assign;

      cmd_executor_set_var(executor, var);
      break;
    }
    default:
      giveup("cmd_exec: not implemented");
    }
  }

  char *argv[argc + 1];
  {
    int i = 0;
    for (GList *node = gargs->next; node != NULL; node = node->next) {
      argv[i] = (char *)node->data;
      i++;
    }

    argv[i] = NULL;
  }

  cmd_executor_fork_exec(executor, file, argv);
}