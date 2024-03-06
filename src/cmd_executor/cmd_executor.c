#include "./cmd_executor.h"
#include "../cmd.h"
#include "../cmd_parser.h"
#include "../utils.h"
#include "./errors.h"
#include "./strings.h"
#include "./vars.h"
#include <fcntl.h>
#include <setjmp.h>
#include <stdio.h>
#include <sys/stat.h>
#include <unistd.h>

// cmd_executor *cmd_executor_new(void) {
//   cmd_executor *executor = malloc(sizeof(cmd_executor));
//   executor->vars = g_hash_table_new(g_str_hash, g_str_equal);
//   executor->stdin_fno = STDIN_FILENO;
//   executor->stdout_fno = STDOUT_FILENO;
//   executor->pg_id = 0;
//   executor->last_pid = 0;

//   return executor;
// }

int cmd_executor_exec_term(cmd_executor *executor, char *term, char **argv) {
  if (strcmp(term, ".") == 0) {
    argv++;

    return cmd_executor_exec_term(executor, argv[0], argv);
  }

  pid_t pid;
  if ((pid = fork()) == 0) {
    if (executor->pg_id != 0) {
      setpgid(0, executor->pg_id);
    }

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

  executor->last_pid = pid;

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

      char *name = var->name;
      char *value = cmd_executor_word_to_str(executor, var->value);

      // If this is the only part of the command, set the var as an executor
      // var.
      if (node->next == NULL) {
        set_var(executor->vars, name, value);
      }
      // Otherwise, set it as a var for the environment for the command.
      else {
        set_var(cmd->env_vars, name, value);
      }

      break;
    }

    case CMD_PART_TYPE_WORD: {
      char *word = cmd_executor_word_to_str(executor, part->value.word);
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

      // Have the executor write to write end of the pipe.
      executor->stdout_fno = pipe_fnos[1];

      if (executor->pg_id == 0) {
        executor->pg_id = getpid();
      }

      // Execute the cmd we built.
      if ((status = cmd_executor_exec_term(
               executor, term, g_list_charptr_to_argv(gargs, argc))) != 0) {
        close(pipe_fnos[0]);
        close(pipe_fnos[1]);

        executor->stdin_fno = original_fnos[0];
        executor->stdout_fno = original_fnos[1];

        executor->pg_id = 0;

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

      // Reset the set pg_id of the executor.
      executor->pg_id = 0;

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
