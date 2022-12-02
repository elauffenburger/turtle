#pragma once

#include "cmd.h"

typedef struct cmd_parser {
  char *next;

  bool in_sub;
} cmd_parser;

cmd_parser *cmd_parser_new(char *cmd_str);

cmd *cmd_parser_parse(cmd_parser *parser, char *input);

cmd *cmd_parser_parse_next(cmd_parser *parser);