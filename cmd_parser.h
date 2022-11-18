#pragma once

#include "cmd.h"

typedef struct cmd_parser {
  char *next;
} cmd_parser;

cmd_parser *cmd_parser_new(void);

cmd *cmd_parser_parse(cmd_parser *parser, char *input);