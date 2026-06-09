/*
 * custom_lstat64.c -- direct lstat64 syscall wrapper for SPARC V8 / Linux 2.6.x
 *
 * Companion to custom_stat64.c (see it for rationale). uclibc-ng's lstat64.c
 * uses statx (360, ENOSYS on 2.6.17); replace lstat64.os with this direct
 * wrapper (syscall 132). SPARC error convention: see custom_fstat64.c.
 */
#define _LARGEFILE64_SOURCE 1
#define _GNU_SOURCE 1
#include <sys/types.h>
#include <sys/stat.h>
#include <errno.h>

#define __NR_lstat64 132

int lstat64(const char *path, struct stat64 *buf)
{
    register long g1 __asm__("g1") = __NR_lstat64;
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
int __GI_lstat64(const char *path, struct stat64 *buf) { return lstat64(path, buf); }
