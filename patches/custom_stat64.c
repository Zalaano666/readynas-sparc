/*
 * custom_stat64.c -- direct stat64 syscall wrapper for SPARC V8 / Linux 2.6.x
 *
 * Problem: uclibc-ng's stat64.c calls statx (syscall 360, Linux 4.11) when
 * __UCLIBC_HAVE_STATX__ is defined. On Linux 2.6.17 statx returns ENOSYS,
 * breaking every file lookup.
 *
 * Fix: replace stat64.os in libc.a with this direct wrapper (syscall 139).
 * Keep stat64 and lstat64 in SEPARATE .os files (1:1 with uclibc's objects):
 * bundling both in stat64.os risks "multiple definition of __GI_lstat64"
 * against uclibc's own lstat64.os, and may let the linker pull the broken
 * statx-based lstat64 instead of this one.
 *
 * SPARC error convention (carry flag): see custom_fstat64.c.
 */
#define _LARGEFILE64_SOURCE 1
#define _GNU_SOURCE 1
#include <sys/types.h>
#include <sys/stat.h>
#include <errno.h>

#define __NR_stat64 139

int stat64(const char *path, struct stat64 *buf)
{
    register long g1 __asm__("g1") = __NR_stat64;
    register long o0 __asm__("o0") = (long)path;
    register long o1 __asm__("o1") = (long)buf;
    __asm__ __volatile__("ta 0x10\n\tbcc 1f\n\tnop\n\tsub %%g0,%%o0,%%o0\n\t1:"
        : "+r"(o0) : "r"(g1), "r"(o1) : "memory", "cc");
    if ((unsigned long)o0 >= (unsigned long)-4095L) {
        errno = (int)-o0;
        return -1;
    }
    return 0;
}
int __GI_stat64(const char *path, struct stat64 *buf) { return stat64(path, buf); }
