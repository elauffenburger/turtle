#include "cmd_executor.h"
#include "cmd.h"
#include "cmd_parser.h"
#include "utils.h"
#include <fcntl.h>
#include <setjmp.h>
#include <stdio.h>
#include <sys/stat.h>
#include <unistd.h>

static char *cmd_executor_word_to_str(cmd_executor *executor, cmd *c,
                                      cmd_word *word);

static void cmd_executor_error(cmd_executor *executor, int status) {
  longjmp(executor->err_jmp, status);
}

cmd_executor *cmd_executor_new() {
  cmd_executor *executor = malloc(sizeof(cmd_executor));
  executor->vars = g_hash_table_new(g_str_hash, g_str_equal);
  executor->stdin_fno = STDIN_FILENO;
  executor->stdout_fno = STDOUT_FILENO;

  return executor;
}

static char *cmd_executor_get_var(cmd_executor *executor,
                                  cmd_word_part_var *var) {
  // Check if we have a var def for the command.
  char *var_val = g_hash_table_lookup(executor->vars, var->name->str);
  if (var_val != NULL) {
    return var_val;
  }

  // Fallback to the environment.
  return getenv(var->name->str);
}

static void set_var(cmd_executor *executor, cmd *c, cmd_var_assign *var,
                    GHashTable *vars) {
  char *value = cmd_executor_word_to_str(executor, c, var->value);

  // Copy the name and value so they don't reference memory owned by the
  // cmd (which will be freed later).
  char *name_cpy = malloc((strlen(var->name) + 1) * sizeof(char));
  char *value_cpy = malloc((strlen(value) + 1) * sizeof(char));
  strcpy(name_cpy, var->name);
  strcpy(value_cpy, value);

  g_hash_table_insert(vars, name_cpy, value_cpy);
}

static char *cmd_executor_word_to_str(cmd_executor *executor, cmd *c,
                                      cmd_word *word) {
  GString *res = g_string_new(NULL);

  for (GList *node = word->parts; node != NULL; node = node->next) {
    cmd_word_part *part = (cmd_word_part *)node->data;

    switch (part->type) {
    case CMD_WORD_PART_TYPE_LIT: {
      res = g_string_append(res, part->value.literal->str);
      break;
    }

    case CMD_WORD_PART_TYPE_STR: {
      cmd_word_part_str *str = part->value.str;
      if (str->quoted) {
        for (GList *str_node = str->parts; str_node != NULL;
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
        for (GList *str_node = str->parts; str_node != NULL;
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

    case CMD_WORD_PART_TYPE_CMD_SUB: {
      // Keep track of the original fnos.
      int original_fnos[2] = {executor->stdin_fno, executor->stdout_fno};

      // Create a pipe.
      int pipe_fnos[2];
      if (pipe(pipe_fnos) < 0) {
        giveup("cmd_executor_exec: pipe failed");
      }

      int status;

      // Write to the write end of the pipe.
      executor->stdout_fno = pipe_fnos[1];
      status = cmd_executor_exec(executor, part->value.cmd_sub);

      // Restore the executor's stdout and close the write end of the pipe.
      executor->stdout_fno = original_fnos[1];
      close(pipe_fnos[1]);

      if (status != 0) {
        cmd_executor_error(executor, status);
      }

      // Read from the read end of the pipe.
      GString *arg = g_string_new(NULL);
      {
        char buf[BUFSIZ];

        ssize_t n;
        while ((n = read(pipe_fnos[0], buf, BUFSIZ)) != 0) {
          // Remove trailing newline.
          if (n < BUFSIZ) {
            buf[n - 1] = 0;
          }

          arg = g_string_append(arg, buf);
        }
      }

      // Close the read end of the pipe.
      close(pipe_fnos[0]);

      res = g_string_append(res, arg->str);

      break;
    }

    case CMD_WORD_PART_TYPE_PROC_SUB: {
      char file_name[] = "/tmp/turtle-proc-XXXXXX";
      int fd;
      if ((fd = mkstemp(file_name)) < 0) {
        giveup("cmd_executor_exec: proc sub file creation failed");
      }

      // Give permission rwx permissions to everyone.
      if (chmod(file_name, 0777) < 0) {
        giveup("cmd_executor_exec: proc sub file chmod failed");
      }

      int original_out_fd = executor->stdout_fno;

      // Redirect executor output to the write end of the pipe.
      executor->stdout_fno = fd;

      // Execute the command.
      int status;
      if ((status = cmd_executor_exec(executor, part->value.proc_sub)) != 0) {
        close(fd);

        executor->stdout_fno = original_out_fd;

        cmd_executor_error(executor, status);
      }

      // Close the file.
      close(fd);

      // Reopen the file with the correct flags.
      if ((fd = open(file_name, O_RDONLY)) < 0) {
        giveup("cmd_executor_exec: proc_sub reopen failed");
      }

      // Restore the original stdout fd.
      executor->stdout_fno = original_out_fd;

      // Append "/dev/fd/{pipe_read_end_fd}"
      g_string_append_printf(res, "%s", file_name);

      break;
    }

    default:
      giveup("cmd_executor_exec: unimplemented cmd_word_part_type");
    }
  }

  return res->str;
}

int cmd_executor_exec_term(cmd_executor *executor, char *term, char **argv) {
  if (strcmp(term, ".") == 0) {
    argv++;

    return cmd_executor_exec_term(executor, argv[0], argv);
  }

  pid_t pid;
  if ((pid = fork()) == 0) {
    if (executor->stdin_fno != STDIN_FILENO) {
      close(STDIN_FILENO);
      dup(executor->stdin_fno);
    }

    if (executor->stdout_fno != STDOUT_FILENO) {
      close(STDOUT_FILENO);
      dup(executor->stdout_fno);
    }

    execvp(term, argv);
    giveup("cmd_executor_exec_term: exec '%s' failed", term);
    exit(1);
  }

  int status;
  if ((pid = waitpid(pid, &status, 0)) < 0) {
    giveup("cmd_executor_exec_term: waitpid failed with pid=%d,status=%d", pid,
           status);
  }

  return status;
}

int cmd_executor_exec(cmd_executor *executor, cmd *cmd) {
  char *term = NULL;

  int argc = 0;
  GList *gargs = NULL;

  // Set up executor err jump.
  int err_status;
  if ((err_status = setjmp(executor->err_jmp)) != 0) {
    return err_status;
  }

  for (GList *node = cmd->parts; node != NULL; node = node->next) {
    cmd_part *part = (cmd_part *)node->data;

    switch (part->type) {
    case CMD_PART_TYPE_VAR_ASSIGN: {
      cmd_var_assign *var = part->value.var_assign;

      // If this is the only part of the command, set the var as an executor
      // var.
      if (node->next == NULL) {
        set_var(executor, cmd, var, executor->vars);
      }
      // Otherwise, set it as a var for the environment for the command.
      else {
        set_var(executor, cmd, var, cmd->env_vars);
      }

      break;
    }

    case CMD_PART_TYPE_WORD: {
      char *word = cmd_executor_word_to_str(executor, cmd, part->value.word);
      if (term == NULL) {
        argc++;

        term = word;
        gargs = g_list_append(gargs, term);
      } else {
        argc++;

        gargs = g_list_append(gargs, word);
      }

      break;
    }

    case CMD_PART_TYPE_PIPE: {
      int status;

      // Keep track of the original fnos.
      int original_fnos[2] = {executor->stdin_fno, executor->stdout_fno};

      // Create a pipe.
      int pipe_fnos[2];
      if (pipe(pipe_fnos) < 0) {
        giveup("cmd_executor_exec: pipe failed");
      }

      // Have the executor write to output of the pipe.
      executor->stdout_fno = pipe_fnos[1];

      // Execute the cmd we built.
      if ((status = cmd_executor_exec_term(
               executor, term, g_list_charptr_to_argv(gargs, argc))) != 0) {
        close(pipe_fnos[0]);
        close(pipe_fnos[1]);

        executor->stdin_fno = original_fnos[0];
        executor->stdout_fno = original_fnos[1];

        return status;
      }

      // Close the pipe output.
      close(pipe_fnos[1]);

      // Have the executor read from the input of the pipe and write to the
      // original out.
      executor->stdin_fno = pipe_fnos[0];
      executor->stdout_fno = original_fnos[1];

      // Execute the piped cmd.
      status = cmd_executor_exec(executor, part->value.piped_cmd);

      // Close the pipe input.
      close(pipe_fnos[0]);

      // Reset the executor stdin.
      executor->stdin_fno = original_fnos[0];

      return status;
    }

    case CMD_PART_TYPE_OR: {
      // Execute the command as-is.
      char **argv = g_list_charptr_to_argv(gargs, argc);
      int status = cmd_executor_exec_term(executor, term, argv);

      // If the result is 0, we're done!
      if (status == 0) {
        return status;
      }

      // Otherwise, execute the or'd command.
      return cmd_executor_exec(executor, part->value.or_cmd);
    }

    case CMD_PART_TYPE_AND: {
      // Execute the command as-is.
      char **argv = g_list_charptr_to_argv(gargs, argc);
      int status = cmd_executor_exec_term(executor, term, argv);

      // If the result non-zero, bail!
      if (status != 0) {
        return status;
      }

      // Otherwise, execute the and'd command.
      return cmd_executor_exec(executor, part->value.and_cmd);
    }

    default:
      giveup("cmd_executor_exec: not implemented");
    }
  }

  if (term == NULL) {
    return 0;
  }

  char **argv = g_list_charptr_to_argv(gargs, argc);
  return cmd_executor_exec_term(executor, term, argv);
}
