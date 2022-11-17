#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <stdarg.h>

void giveup(char *fmt, ...) {
  va_list args;
  va_start(args, fmt);

  char full_fmt[BUFSIZ];
  snprintf(full_fmt, BUFSIZ, "%s\n", fmt);

  vfprintf(stderr, full_fmt, args);
  va_end(args);

  perror("");

  exit(1);
}
