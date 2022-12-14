#include "cmd_executor.h"
#include <setjmp.h>

void cmd_executor_error(cmd_executor *executor, int status) {
  longjmp(executor->err_jmp, status);
}