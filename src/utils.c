#include "glib.h"
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/errno.h>
#include <unistd.h>

void giveup(char *fmt, ...) {
  va_list args;
  va_start(args, fmt);

  char full_fmt[BUFSIZ];
  snprintf(full_fmt, BUFSIZ, "%s\n", fmt);

  vfprintf(stderr, full_fmt, args);
  va_end(args);

  if (errno != 3) {
    perror("");
  }

  exit(1);
}

char **g_list_charptr_to_argv(GList *list, int argc) {
  char **argv = malloc((unsigned long)(argc + 1) * sizeof(char *));

  int i = 0;
  for (GList *node = list; node != NULL; node = node->next) {
    argv[i] = (char *)node->data;
    i++;
  }

  argv[i] = NULL;

  return argv;
}