/*
 * termshim: the terminfo lookups mosh-client makes, answered for the terminal
 * it always runs in on Android (xterm.js, TERM=xterm-256color).
 *
 * Unknown capabilities answer as terminfo does for an absent one: 0 for a
 * flag, -1 for a number, NULL for a string.
 *
 * Copyright (c) 2026 Daniel Koch. MIT License (see LICENSE).
 */
#include <string.h>
#include "term.h"

int setupterm(const char *term, int fildes, int *errret) {
    (void)term;
    (void)fildes;
    if (errret) *errret = 1;
    return OK;
}

int tigetflag(const char *capname) {
    /* Background colour erase: xterm.js fills erased cells with the current background. */
    if (strcmp(capname, "bce") == 0) return 1;
    return 0;
}

int tigetnum(const char *capname) {
    if (strcmp(capname, "colors") == 0) return 256;
    return -1;
}

char *tigetstr(const char *capname) {
    /* Erase characters. */
    if (strcmp(capname, "ech") == 0) return (char *)"\033[%p1%dX";
    /* Alternate screen: unused when MOSH_NO_TERM_INIT is set, which OrangeSSH does. */
    if (strcmp(capname, "smcup") == 0) return (char *)"\033[?1049h";
    if (strcmp(capname, "rmcup") == 0) return (char *)"\033[?1049l";
    return NULL;
}
