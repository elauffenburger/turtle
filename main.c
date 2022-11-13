#include "cmd.h"
#include "glib.h"
#include "utils.h"
#include <stdio.h>
#include <unistd.h>

void onexit() {
  fputs("bye!\n", stderr);
  exit(0);
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

    cmd = cmd_parse_line(buf);
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