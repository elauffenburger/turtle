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
  cmd_parser *parser = cmd_parser_new();

  if (signal(SIGINT, SIG_IGN) != SIG_IGN) {
    signal(SIGINT, onexit);
  }

  for (;;) {
    if (fgets(buf, sizeof(buf), stdin) == NULL) {
      giveup("failed to read from stdin");
    }

    if ((cmd = cmd_parser_parse(parser, buf)) == NULL) {
      giveup(sprintf("failed to parse command: %s", parser->err));
    }

    cmd_exec(cmd);

    break;
  }

  exit(0);
}