#ifndef RIPGREP_V_CPU_FEATURES_SHIM_H
#define RIPGREP_V_CPU_FEATURES_SHIM_H

#if defined(_MSC_VER) && (defined(_M_X64) || defined(_M_IX86))
#include <intrin.h>

static int rg_runtime_sse2(void) {
#if defined(_M_X64)
    return 1;
#else
    int regs[4];
    __cpuid(regs, 1);
    return (regs[3] & (1 << 26)) != 0;
#endif
}

static int rg_runtime_ssse3(void) {
    int regs[4];
    __cpuid(regs, 1);
    return (regs[2] & (1 << 9)) != 0;
}

static int rg_runtime_avx2(void) {
    int regs[4];
    __cpuid(regs, 1);
    if ((regs[2] & (1 << 27)) == 0 || (regs[2] & (1 << 28)) == 0) {
        return 0;
    }
    if ((_xgetbv(0) & 0x6) != 0x6) {
        return 0;
    }
    __cpuidex(regs, 7, 0);
    return (regs[1] & (1 << 5)) != 0;
}
#elif (defined(__x86_64__) || defined(__i386__)) && \
      (defined(__GNUC__) || defined(__clang__))
static int rg_runtime_sse2(void) {
    __builtin_cpu_init();
    return __builtin_cpu_supports("sse2") != 0;
}

static int rg_runtime_ssse3(void) {
    __builtin_cpu_init();
    return __builtin_cpu_supports("ssse3") != 0;
}

static int rg_runtime_avx2(void) {
    __builtin_cpu_init();
    return __builtin_cpu_supports("avx2") != 0;
}
#else
static int rg_runtime_sse2(void) { return 0; }
static int rg_runtime_ssse3(void) { return 0; }
static int rg_runtime_avx2(void) { return 0; }
#endif

static int rg_compile_sse2(void) {
#if defined(__x86_64__) || defined(_M_X64) || defined(__SSE2__) || \
    (defined(_M_IX86_FP) && _M_IX86_FP >= 2)
    return 1;
#else
    return 0;
#endif
}

static int rg_compile_ssse3(void) {
#if defined(__SSSE3__)
    return 1;
#else
    return 0;
#endif
}

static int rg_compile_avx2(void) {
#if defined(__AVX2__) || defined(_M_AVX2)
    return 1;
#else
    return 0;
#endif
}

#endif
