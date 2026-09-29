/*
 * termshim: see curses.h.
 *
 * Copyright (c) 2026 Daniel Koch. MIT License (see LICENSE).
 */
#ifndef TERMSHIM_TERM_H
#define TERMSHIM_TERM_H

#include "curses.h"

#ifdef __cplusplus
extern "C" {
#endif

int setupterm(const char *term, int fildes, int *errret);
int tigetflag(const char *capname);
int tigetnum(const char *capname);
char *tigetstr(const char *capname);

#ifdef __cplusplus
}
#endif

#endif
