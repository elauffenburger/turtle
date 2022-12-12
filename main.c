#include "cmd.h"
#include "cmd_executor/cmd_executor.h"
#include "cmd_parser.h"
#include "glib.h"
#include "utils.h"
#include <locale.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <wchar.h>

#pragma clang diagnostic ignored "-Weverything"
#pragma clang diagnostic push
#include <readline/history.h>
#include <readline/readline.h>
#pragma clang diagnostic pop

void onexit(int signal) {
  fputs("bye!\n", stderr);
  exit(0);
}

int main(int argc, char **argv) {
  // Set up signal handlers.
  if (signal(SIGINT, SIG_IGN) != SIG_IGN) {
    signal(SIGINT, onexit);
  }

  // Parse args.
  char *cmd_str = NULL;
  unsigned int sleep_time = 0;
  char *script_filename = NULL;
  GList *gargs = NULL;

  for (int i = 1; i < argc; i++) {
    if (strcmp(argv[i], "-c") == 0) {
      i++;
      cmd_str = argv[i];
    } else if (strcmp(argv[i], "--sleep") == 0) {
      i++;
      sleep_time = (unsigned int)atoi(argv[i]);
    } else {
      if (script_filename == NULL) {
        script_filename = argv[i];
      } else {
        gargs = g_list_append(gargs, argv[i]);
      }
    }
  }

  if (sleep_time > 0) {
    sleep(sleep_time);
  }

  if (script_filename != NULL) {
    cmd_parser *parser = cmd_parser_new();
    cmd_executor *executor = cmd_executor_new();
    int status;

    FILE *script_file = fopen(script_filename, "r");

    char line[BUFSIZ];
    while ((fgets(line, sizeof(line), script_file)) != NULL) {
      cmd_parser_set_next(parser, line);

      cmd *cmd;
      while ((cmd = cmd_parser_parse_next(parser)) != NULL) {
        if ((status = cmd_executor_exec(executor, cmd)) != 0) {
          return status;
        }

        cmd_free(cmd);
      }
    }

    exit(0);
  }

  // If the user specified a single command, run it!
  if (cmd_str != NULL) {
    cmd_parser *parser = cmd_parser_new();
    cmd_parser_set_next(parser, cmd_str);
    cmd_executor *executor = cmd_executor_new();

    cmd *cmd;
    while ((cmd = cmd_parser_parse_next(parser)) != NULL) {
      int status;
      if ((status = cmd_executor_exec(executor, cmd)) != 0) {
        exit(status);
      }
    }

    exit(0);
  }

  // Otherwise, we're in interactive mode.
  cmd_parser *parser = cmd_parser_new();
  cmd_executor *executor = cmd_executor_new();
  char *line = NULL;
  int status;
  for (;;) {
    if (line) {
      free(line);
      line = NULL;
    }

    line = readline("🐢> ");
    if (line && *line) {
      add_history(line);
    }

    cmd_parser_set_next(parser, line);

    cmd *cmd;
    while ((cmd = cmd_parser_parse_next(parser)) != NULL) {
      if ((status = cmd_executor_exec(executor, cmd)) != 0) {
        return status;
      }

      cmd_free(cmd);
    }
  }

  exit(0);
}