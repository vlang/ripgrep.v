#ifndef RIPGREP_V_REGEX_MEMORY_SHIM_H
#define RIPGREP_V_REGEX_MEMORY_SHIM_H

#include <stddef.h>
#include <string.h>

static inline void *rg_memmem(void *haystack, size_t haystack_len,
                              void *needle, size_t needle_len) {
    unsigned char *bytes = (unsigned char *)haystack;
    if (needle_len == 0) {
        return haystack;
    }
    if (needle_len > haystack_len) {
        return NULL;
    }
    for (size_t i = 0; i <= haystack_len - needle_len; i++) {
        if (memcmp(bytes + i, needle, needle_len) == 0) {
            return bytes + i;
        }
    }
    return NULL;
}

static inline void *rg_memchr(void *bytes, int byte, size_t len) {
    return memchr(bytes, byte, len);
}

static inline int rg_memcmp(void *left, void *right, size_t len) {
    return memcmp(left, right, len);
}

#endif
