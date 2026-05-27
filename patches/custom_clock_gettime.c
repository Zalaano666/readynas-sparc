/*
 * custom_clock_gettime.c — clock_gettime fallback for SPARC V8 / Linux 2.6.x
 *
 * uclibc-ng with __UCLIBC_USE_TIME64__ uses clock_gettime64 (403, Linux 5.1).
 * Linux 2.6.17 returns ENOSYS.
 *
 * clock_gettime (263) and gettimeofday (116) both write 32-bit structs, but
 * uclibc TIME64 defines struct timespec/timeval with int64_t tv_sec — passing
 * them directly causes a struct layout mismatch in big-endian.
 *
 * Fix: use a local 32-bit-safe struct for the syscall and widen manually.
 * We implement CLOCK_MONOTONIC via gettimeofday (always available on 2.6.17)
 * — wall clock is fine for BusyBox TLS timeout arithmetic.
 */
#define _GNU_SOURCE 1
#include <time.h>
#include <errno.h>
#include <stdint.h>

#define __NR_gettimeofday 116

struct __ktimeval32 { int32_t tv_sec; int32_t tv_usec; };

int clock_gettime(clockid_t clk_id, struct timespec *tp)
{
    struct __ktimeval32 tv;
    register long g1 __asm__("g1") = __NR_gettimeofday;
    register long o0 __asm__("o0") = (long)&tv;
    register long o1 __asm__("o1") = 0;
    __asm__ __volatile__("ta 0x10"
        : "+r"(o0) : "r"(g1), "r"(o1) : "memory", "cc");
    if ((unsigned long)o0 >= (unsigned long)-4095L) {
        errno = (int)-o0;
        return -1;
    }
    tp->tv_sec  = tv.tv_sec;
    tp->tv_nsec = tv.tv_usec * 1000;
    return 0;
}

int __libc_clock_gettime(clockid_t clk_id, struct timespec *tp)
{
    return clock_gettime(clk_id, tp);
}
