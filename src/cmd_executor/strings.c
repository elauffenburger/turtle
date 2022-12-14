#include "../utils.h"
#include "cmd_executor.h"
#include "errors.h"
#include "glib.h"
#include "vars.h"
#include <fcntl.h>
#include <stdio.h>
#include <sys/stat.h>
#include <unistd.h>

char *cmd_executor_word_to_str(cmd_executor *executor, cmd_word *word) {
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
            GString *val =
                cmd_executor_get_var(executor, str_part->value.var->name->str);
            if (val != NULL) {
              res = g_string_append(res, g_string_free(val, false));
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
      GString *val = cmd_executor_get_var(executor, part->value.var->name->str);
      if (val != NULL) {
        res = g_string_append(res, g_string_free(val, false));
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