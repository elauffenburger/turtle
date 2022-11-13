#include <stdio.h>
#include <stdlib.h>

void giveup(char *prog, char *msg) {
  fprintf(stderr, "%s\n", msg);
  perror(prog);

  exit(1);
}
