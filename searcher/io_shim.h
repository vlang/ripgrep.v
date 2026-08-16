#ifndef RIPGREP_V_SEARCHER_IO_SHIM_H
#define RIPGREP_V_SEARCHER_IO_SHIM_H

#include <stddef.h>
#include <stdint.h>
#include <sys/types.h>
#include <unistd.h>

static inline ptrdiff_t rg_pread(int fd, void *buf, size_t count,
                                 int64_t offset) {
    return (ptrdiff_t)pread(fd, buf, count, (off_t)offset);
}

#endif
