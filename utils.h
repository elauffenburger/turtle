#pragma once

#include "glib.h"

void giveup(char *fmt, ...);

char **g_list_charptr_to_argv(GList *list, int argc);