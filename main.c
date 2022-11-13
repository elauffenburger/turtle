#include "glib.h"
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

void giveup(char *prog, char *msg) {
  fprintf(stderr, "%s\n", msg);
  perror(prog);

  exit(1);
}

void onexit() {
  fputs("bye!\n", stderr);
  exit(0);
}

typedef enum cmd_type { CMD_TYPE_PROC_SUB, CMD_TYPE_LIT } cmd_type;

typedef struct cmd_proc_sub {

} cmd_proc_sub;

typedef struct cmd_lit {
  char *prog;

  GList *gargs;
} cmd_lit;

typedef struct cmd {
  cmd_type type;
  char *err;

  union cmd_value {
    cmd_proc_sub proc_sub;
    cmd_lit lit;
  } value;
} cmd;

int cmd_lit_argc(cmd_lit *cmd) { return g_list_length(cmd->gargs) + 1; }

void cmd_lit_argv(cmd_lit *cmd, char **args) {
  int num_args = cmd_lit_argc(cmd);
  GList *garg = cmd->gargs->next;

  args[0] = cmd->prog;

  int arg_i = 1;
  for (;;) {
    if (garg == NULL) {
      break;
    }

    args[arg_i] = ((GString *)(garg->data))->str;

    garg = garg->next;
    arg_i++;
  }

  args[num_args] = "\0";
}

cmd *parse_cmd(char *input) {
  char *next = input;

  GString *buf = g_string_new(NULL);
  GList *args = NULL;

  for (; *next != '\0'; next++) {
    switch (*next) {
    case ' ':
    case '\n':
      // We're done parsing an arg!

      // Add the arg and reset the buf.
      args = g_list_append(args, buf);
      buf = g_string_new(NULL);

      break;

    default:
      // Append to the buffer.
      buf = g_string_append_c(buf, *next);
    }
  }

  cmd *cmd = malloc(sizeof(cmd));
  cmd->err = NULL;
  cmd->type = CMD_TYPE_LIT;

  cmd_lit lit;
  GString *prog = (GString *)args->data;
  lit.prog = prog->str;
  lit.gargs = args;

  cmd->value.lit = lit;

  return cmd;
}

int main(int argc, char **argv) {
  char buf[BUFSIZ];
  cmd *cmd;

  if (signal(SIGINT, SIG_IGN) != SIG_IGN) {
    signal(SIGINT, onexit);
  }

  for (;;) {
    if (fgets(buf, sizeof(buf), stdin) == NULL) {
      giveup(argv[0], "failed to read from stdin");
    }

    cmd = parse_cmd(buf);
    if (cmd->err != NULL) {
      giveup(argv[0], cmd->err);
    }

    switch (cmd->type) {
    case CMD_TYPE_LIT: {
      cmd_lit lit = cmd->value.lit;

      int pid = 0;
      int status = 0;

      if ((pid = fork()) < 0) {
        giveup(argv[0], "failed to fork");
      } else if (pid == 0) {
        char *args[cmd_lit_argc(&lit)];
        cmd_lit_argv(&lit, args);

        execvp(lit.prog, args);

        // Failed to exec.
        giveup(argv[0], "failed to exec");
      }

      if ((pid = waitpid(pid, &status, 0)) < 0) {
        giveup(argv[0], "failed to wait for process to complete");
      }

      break;
    }
    default:
      giveup(argv[0], "not implemented");
    }
  }

  exit(1);
}