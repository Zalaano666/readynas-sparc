/*
 * custom_stat64.c — direct stat64/lstat64 syscall wrappers for SPARC V8 / Linux 2.6.x
 *
 * Problem: uclibc-ng's stat64.c and lstat64.c call statx (syscall 360, added
 * in Linux 4.11) when __UCLIBC_HAVE_STATX__ is defined. The Linux 7.x headers
 * used by buildroot define __NR_statx, which enables this path. On Linux 2.6.17
 * statx returns ENOSYS, breaking every file lookup.
 *
 * Fix: replace stat64.os and lstat64.os in libc.a with these direct wrappers.
 *   stat64  = SPARC syscall 139
 *   lstat64 = SPARC syscall 132
 */
#define _LARGEFILE64_SOURCE 1
#define _GNU_SOURCE 1
#include <sys/types.h>
#include <sys/stat.h>
#include <errno.h>

#define __NR_stat64  139
#define __NR_lstat64 132

#define SYSCALL2(nr, a, b) ({                                       \
    register long _g1 __asm__("g1") = (long)(nr);                  \
    register long _o0 __asm__("o0") = (long)(a);                   \
    register long _o1 __asm__("o1") = (long)(b);                   \
    __asm__ __volatile__("ta 0x10"                                  \
        : "+r"(_o0) : "r"(_g1), "r"(_o1) : "memory", "cc");       \
    if ((unsigned long)_o0 >= (unsigned long)-4095L) {             \
        errno = (int)-_o0; _o0 = -1;                               \
    }                                                               \
    (int)_o0; })

int stat64(const char *path, struct stat64 *buf)
{
    return SYSCALL2(__NR_stat64, path, buf);
}
int __GI_stat64(const char *path, struct stat64 *buf) { return stat64(path, buf); }

int lstat64(const char *path, struct stat64 *buf)
{
    return SYSCALL2(__NR_lstat64, path, buf);
}
int __GI_lstat64(const char *path, struct stat64 *buf) { return lstat64(path, buf); }
