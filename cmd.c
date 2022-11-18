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

cmd_word_part *cmd_word_get_part(cmd_word *word, int part_num) {
  int i = 0;
  GList *node = word->parts->next;
  for (;;) {
    if (i == part_num) {
      return (cmd_word_part *)node->data;
    }

    node = node->next;
    i++;
  }

  return NULL;
}

cmd *cmd_new(void) {
  cmd *cmd = malloc(sizeof(cmd));
  cmd->parts = g_list_alloc();

  return cmd;
}
