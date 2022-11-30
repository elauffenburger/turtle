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
  cmd *c = malloc(sizeof(cmd));
  c->parts = NULL;
  c->vars = g_hash_table_new(g_str_hash, g_str_equal);
  c->env_vars = g_hash_table_new(g_str_hash, g_str_equal);

  return c;
}

void cmd_word_part_str_part_free(cmd_word_part_str_part *part) {
  switch (part->type) {
  case CMD_WORD_PART_STR_PART_TYPE_LITERAL: {
    g_string_free(part->value.literal, true);
    break;
  }

  case CMD_WORD_PART_STR_PART_TYPE_VAR: {
    g_string_free(part->value.var->name, true);
    free(part->value.var);
    break;
  }
  }

  free(part);
}

void cmd_word_part_free(cmd_word_part *part) {
  switch (part->type) {
  case CMD_WORD_PART_TYPE_LIT: {
    g_string_free(part->value.literal, true);
    break;
  }

  case CMD_WORD_PART_TYPE_STR: {
    for (GList *node = part->value.str->parts; node != NULL;
         node = node->next) {
    }
    g_list_free_full(part->value.str->parts,
                     (GDestroyNotify)cmd_word_part_str_part_free);
    free(part->value.str);
    break;
  }

  case CMD_WORD_PART_TYPE_VAR: {
    g_string_free(part->value.var->name, true);
    free(part->value.var);
    break;
  }

  case CMD_WORD_PART_TYPE_PROC_SUB: {
    cmd_free(part->value.proc_sub);
    break;
  }

  default:
    fprintf(stderr, "cmd_word_part_free: unknown word part type\n");
  }

  free(part);
}

void cmd_word_free(cmd_word *word) {
  g_list_free_full(word->parts, (GDestroyNotify)cmd_word_part_free);
  free(word);
}

void cmd_part_free(cmd_part *part) {
  switch (part->type) {
  case CMD_PART_TYPE_VAR_ASSIGN: {
    free(part->value.var_assign->name);
    cmd_word_free(part->value.var_assign->value);
    free(part->value.var_assign);
    break;
  }

  case CMD_PART_TYPE_WORD: {
    cmd_word_free(part->value.word);
    break;
  }

  case CMD_PART_TYPE_PIPE: {
    cmd_free(part->value.piped_cmd);
    break;
  }

  default:
    fprintf(stderr, "cmd_word_free: unknown part type\n");
  }

  free(part);
}

void cmd_free(cmd *cmd) {
  g_list_free_full(cmd->parts, (GDestroyNotify)cmd_part_free);
  free(cmd);
}
