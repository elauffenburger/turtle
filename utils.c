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
