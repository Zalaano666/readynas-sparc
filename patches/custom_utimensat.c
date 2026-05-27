/*
 * custom_utimensat.c — utimensat fallback for SPARC V8 / Linux 2.6.x
 *
 * Problem: utimensat (syscall 310) was added in Linux 2.6.22. Linux 2.6.17
 * returns ENOSYS. Git uses utimensat during checkout to set file mtimes.
 *
 * Fix: replace utimensat.os in libc.a with this wrapper that falls back to
 * utimes() (syscall 271, present since Linux 2.6.x).
 *
 * Limitations:
 *  - AT_SYMLINK_NOFOLLOW on symlinks: treated same as regular files (utimes
 *    follows symlinks, so symlink mtime is not set — acceptable for git).
 *  - AT_EMPTY_PATH (fd-based, no path): silently ignored. /proc/self/fd is
 *    not available on Linux 2.6.17. Not used by git on bare repos.
 *  - UTIME_OMIT for one component only: the omitted component is left at
 *    epoch 0 rather than preserved. Git does not mix NOW and OMIT in practice.
 */
#define _GNU_SOURCE 1
#include <sys/time.h>
#include <fcntl.h>
#include <errno.h>

#ifndef UTIME_NOW
#define UTIME_NOW  ((1l << 30) - 1l)
#define UTIME_OMIT ((1l << 30) - 2l)
#endif

#define __NR_utimes 271

static int _utimes(const char *path, const struct timeval tv[2])
{
    register long g1 __asm__("g1") = __NR_utimes;
    register long o0 __asm__("o0") = (long)path;
    register long o1 __asm__("o1") = (long)tv;
    __asm__ __volatile__("ta 0x10"
        : "+r"(o0) : "r"(g1), "r"(o1) : "memory", "cc");
    if ((unsigned long)o0 >= (unsigned long)-4095L) {
        errno = (int)-o0;
        return -1;
    }
    return 0;
}

int utimensat(int dirfd, const char *path,
              const struct timespec ts[2], int flags)
{
    struct timeval tv[2];
    struct timeval *tvp = tv;

    /* No path (AT_EMPTY_PATH fd-only): can't emulate without /proc — skip */
    if (!path || !*path)
        return 0;

    if (!ts) {
        tvp = NULL;  /* NULL → set both to current time */
    } else if (ts[0].tv_nsec == UTIME_NOW && ts[1].tv_nsec == UTIME_NOW) {
        tvp = NULL;
    } else if (ts[0].tv_nsec == UTIME_OMIT && ts[1].tv_nsec == UTIME_OMIT) {
        return 0;    /* Nothing to do */
    } else {
        tv[0].tv_sec  = (ts[0].tv_nsec == UTIME_OMIT) ? 0 : ts[0].tv_sec;
        tv[0].tv_usec = (ts[0].tv_nsec == UTIME_OMIT) ? 0 : ts[0].tv_nsec / 1000;
        tv[1].tv_sec  = (ts[1].tv_nsec == UTIME_OMIT) ? 0 : ts[1].tv_sec;
        tv[1].tv_usec = (ts[1].tv_nsec == UTIME_OMIT) ? 0 : ts[1].tv_nsec / 1000;
        /* If either component is NOW, fall back to "set both to now" */
        if (ts[0].tv_nsec == UTIME_NOW || ts[1].tv_nsec == UTIME_NOW)
            tvp = NULL;
    }

    return _utimes(path, tvp);
}
