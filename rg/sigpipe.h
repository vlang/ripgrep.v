#ifndef RIPGREP_V_RG_SIGPIPE_H
#define RIPGREP_V_RG_SIGPIPE_H

#ifndef _WIN32
#include <signal.h>

static inline void rg_ignore_sigpipe(void) {
	signal(SIGPIPE, SIG_IGN);
}
#endif

#endif
