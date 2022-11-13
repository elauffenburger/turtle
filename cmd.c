#include "cmd.h"
#include "glib.h"
#include "utils.h"

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

cmd *cmd_parse_line(char *input) {
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