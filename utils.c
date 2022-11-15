#include <stdio.h>
#include <stdlib.h>

void giveup(char *msg) {
  fprintf(stderr, "%s\n", msg);
  perror("");

  exit(1);
}
