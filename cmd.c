#include "cmd.h"
#include "cmd_executor.h"
#include "glib.h"
#include "utils.h"
#include <stdbool.h>
#include <stdio.h>
#include <unistd.h>

cmd_word_part *cmd_word_part_new(cmd_word_part_type type,
                                 cmd_word_part_value val) {
  cmd_word_part *part = malloc(sizeof(cmd_word_part));
  part->type = type;
  part->value = val;

  return part;
}

cmd *cmd_new(void) {
  cmd *cmd = malloc(sizeof(cmd));
  cmd->parts = g_list_alloc();

  return cmd;
}

void cmd_exec(cmd *cmd) {
  cmd_executor *executor = cmd_executor_new();

  char *file = NULL;

  int argc = 0;
  GList *gargs = g_list_alloc();

  for (GList *node = cmd->parts->next; node != NULL; node = node->next) {
    cmd_part *part = (cmd_part *)node->data;

    switch (part->type) {
    case CMD_PART_TYPE_WORD: {
      char *word = cmd_executor_word_to_str(executor, part->value.word);
      if (file == NULL) {
        argc++;

        file = word;
        gargs = g_list_append(gargs, file);
      } else {
        argc++;

        gargs = g_list_append(gargs, word);
      }

      break;
    }
    default:
      giveup("not implemented");
    }
  }

  char *argv[argc + 1];
  {
    int i = 0;
    for (GList *node = gargs->next; node != NULL; node = node->next) {
      argv[i] = (char *)node->data;
      i++;
    }

    argv[i] = NULL;
  }

  cmd_executor_exec(executor, file, argv);
}