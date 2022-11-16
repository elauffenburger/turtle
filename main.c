#include "cmd.h"
#include "cmd_parser.h";
#include "glib.h"
#include "utils.h"
#include <locale.h>
#include <stdio.h>
#include <unistd.h>
#include <wchar.h>

void onexit(int signal) {
  fputs("bye!\n", stderr);
  exit(0);
}

int main() {
  char buf[BUFSIZ];
  cmd *cmd;
  cmd_parser *parser = cmd_parser_new();

  if (signal(SIGINT, SIG_IGN) != SIG_IGN) {
    signal(SIGINT, onexit);
  }

  for (;;) {
    printf("🐢> ");
    fflush(stdout);

    if (fgets(buf, sizeof(buf), stdin) == NULL) {
      giveup("failed to read from stdin");
    }

    if ((cmd = cmd_parser_parse(parser, buf)) == NULL) {
      giveup("parsing failed");
    }

    cmd_exec(cmd);
  }

  exit(0);
}