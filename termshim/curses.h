/*
 * termshim: the few curses/terminfo entry points mosh-client uses, answered
 * for xterm-256color. Android has no ncurses and no terminfo database, and
 * mosh-client only ever runs here inside OrangeSSH's xterm.js terminal.
 *
 * Copyright (c) 2026 Daniel Koch. MIT License (see LICENSE).
 */
#ifndef TERMSHIM_CURSES_H
#define TERMSHIM_CURSES_H

#define OK 0
#define ERR (-1)

#endif
