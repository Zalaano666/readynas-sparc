/*
 * custom_fstat64.c — direct fstat64 syscall wrapper for SPARC V8 / Linux 2.6.x
 *
 * Problem: uclibc-ng is built with Linux 7.x headers that define
 * __UCLIBC_USE_TIME64__ and LINUX_VERSION_CODE > 5.1.0, which disables the
 * direct fstat64 syscall branch in fstat64.c. The statx fallback branch is
 * also dead because statx (360) is ENOSYS on Linux 2.6.17. fstat64.os
 * therefore compiles to nothing, leaving __GI_fstat64 undefined — required
 * by opendir, ttyname, fstatfs, etc.
 *
 * Fix: replace fstat64.os in libc.a with this direct syscall wrapper.
 * SPARC syscall ABI: number in %g1, args in %o0–%o5, trap via "ta 0x10",
 * result in %o0 (negative = –errno).
 */
#define _LARGEFILE64_SOURCE 1
#define _GNU_SOURCE 1
#include <sys/types.h>
#include <sys/stat.h>
#include <errno.h>

#define __NR_fstat64 63

int fstat64(int fd, struct stat64 *buf)
{
    register long g1 __asm__("g1") = __NR_fstat64;
    register long o0 __asm__("o0") = (long)fd;
    register long o1 __asm__("o1") = (long)buf;
    __asm__ __volatile__("ta 0x10"
        : "+r"(o0) : "r"(g1), "r"(o1) : "memory", "cc");
    if ((unsigned long)o0 >= (unsigned long)-4095L) {
        errno = (int)-o0;
        return -1;
    }
    return 0;
}

/* Internal hidden alias used by other libc modules */
int __GI_fstat64(int fd, struct stat64 *buf) { return fstat64(fd, buf); }
