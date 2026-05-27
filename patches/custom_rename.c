/*
 * custom_rename.c — direct rename syscall wrapper for SPARC V8 / Linux 2.6.x
 *
 * Problem: uclibc-ng's rename.c falls through to the renameat2 branch
 * (syscall 345, Linux 3.15+) because __NR_renameat2 is defined in the
 * Linux 7.x headers used by buildroot. On Linux 2.6.17 renameat2 returns
 * ENOSYS. Symptom when using git: "error: couldn't set 'refs/heads/main'"
 * on every push.
 *
 * Fix: replace rename.os in libc.a with this direct wrapper.
 *   rename = SPARC syscall 128
 */
#include <errno.h>

#define __NR_rename 128

int rename(const char *oldpath, const char *newpath)
{
    register long g1 __asm__("g1") = __NR_rename;
    register long o0 __asm__("o0") = (long)oldpath;
    register long o1 __asm__("o1") = (long)newpath;
    __asm__ __volatile__("ta 0x10"
        : "+r"(o0) : "r"(g1), "r"(o1) : "memory", "cc");
    if ((unsigned long)o0 >= (unsigned long)-4095L) {
        errno = (int)-o0;
        return -1;
    }
    return 0;
}
