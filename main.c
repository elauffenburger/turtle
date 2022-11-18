#include "cmd.h"
#include "cmd_executor.h"
#include "cmd_parser.h"
#include "glib.h"
#include "utils.h"
#include <locale.h>
#include <stdio.h>
#include <unistd.h>
#include <wchar.h>

#pragma clang diagnostic ignored "-Wunused-parameter"
#pragma clang diagnostic push
void onexit(int signal) {
  fputs("bye!\n", stderr);
  exit(0);
}
#pragma clang diagnostic pop

int main(int argc, char **argv) {
  cmd_parser *parser = cmd_parser_new();

  // Set up signal handlers.
  if (signal(SIGINT, SIG_IGN) != SIG_IGN) {
    signal(SIGINT, onexit);
  }

  // Parse args.
  char *cmd_str = NULL;
  unsigned int sleep_time = 0;

  for (int i = 1; i < argc; i++) {
    if (strcmp(argv[i], "-c") == 0) {
      i++;
      cmd_str = argv[i];
    } else if (strcmp(argv[i], "--sleep") == 0) {
      i++;
      sleep_time = (unsigned int)atoi(argv[i]);
    } else {
      giveup("unknown arg %s", argv[i]);
    }
  }

  if (sleep_time > 0) {
    sleep(sleep_time);
  }

  // If the user specified a single command, run it!
  if (cmd_str != NULL) {
    cmd *cmd;
    if ((cmd = cmd_parser_parse(parser, cmd_str)) == NULL) {
      giveup("parsing failed");
    }

    cmd_executor *executor = cmd_executor_new();
    cmd_executor_exec(executor, cmd);

    exit(0);
  }

  // Otherwise, we're in interactive mode.
  char buf[BUFSIZ];
  for (;;) {
    printf("🐢> ");
    fflush(stdout);

    if (fgets(buf, sizeof(buf), stdin) == NULL) {
      giveup("failed to read from stdin");
    }

    cmd *cmd;
    if ((cmd = cmd_parser_parse(parser, buf)) == NULL) {
      giveup("parsing failed");
    }

    cmd_executor *executor = cmd_executor_new();
    cmd_executor_exec(executor, cmd);
  }
}