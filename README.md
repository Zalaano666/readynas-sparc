# git 2.54.0 for Netgear ReadyNAS (SPARC V8 / Linux 2.6.17)

Cross-compiled static git binary and build instructions for the Netgear ReadyNAS
family based on the **Infrant Technologies NEON IT3107 SoC** (plain SPARC V8,
~256 MB RAM, Linux 2.6.17.14, glibc 2.3.2).

The stock firmware ships with a very old git version. A pre-built git 2.21.0
(2019) was previously available thanks to
[mfe-/ReadyNASDuoSparc](https://github.com/mfe-/ReadyNASDuoSparc) — the
go-to resource for ReadyNAS SPARC binaries. This repo picks up where that left
off, building git **2.54.0** with a newer toolchain that correctly targets plain
SPARC V8.

## Quick install (pre-built binary)

Download the tarball from the [Releases](https://github.com/Zalaano666/readynas-sparc-git/releases) page and extract it
on your NAS:

```sh
scp git-2.54.0-sparc.tar.gz root@<NAS_IP>:/tmp/
ssh root@<NAS_IP> 'tar xzf /tmp/git-2.54.0-sparc.tar.gz -C / && git --version'
```

First-time setup — allow git to operate on repos owned by the `git` user:

```sh
ssh root@<NAS_IP> '
for h in /root /c/home/git; do
  printf "[safe]\n    directory = *\n" > $h/.gitconfig
  chown $(stat -c "%u:%g" $h) $h/.gitconfig
done'
```

## Build from source

Requires an x86-64 Ubuntu/Debian host with ~10 GB free disk space and sudo.

```sh
git clone https://github.com/YOUR_USERNAME/readynas-sparc-git
cd readynas-sparc-git
sudo sh build.sh          # full build including toolchain (~1–2 hours)
# or, if buildroot toolchain is already built:
sudo sh build.sh git-only # ~10 minutes
```

Output: `/tmp/git-2.54.0-sparc.tar.gz`

## Why this is hard

### CPU architecture

The IT3107 SoC is **plain SPARC V8** (`e_machine = 0x0002`). This is not
SPARC32Plus (sparcv8+, `e_machine = 0x0012`). The kernel returns `ENOEXEC` for
any binary with the wrong ELF machine type. The standard Debian `sparc` port
produces SPARC32Plus — it cannot be used as the build target.

The only verified working toolchain is **buildroot + uclibc-ng** with
`BR2_sparc_v8=y`. musl-libc does not support sparc32.

### Linux 2.6.17 syscall gaps

buildroot uses Linux 7.x kernel headers, which define syscall numbers for
interfaces added long after Linux 2.6.17. uclibc-ng silently selects the newer
syscalls at compile time. Five object files in `libc.a` must be replaced with
direct wrappers before linking:

| Replaced file | Broken syscall | Added in | Direct fallback |
|---|---|---|---|
| `fstat64.os` | statx (360) + TIME64 interaction | Linux 4.11 | fstat64 (63) |
| `stat64.os` | statx (360) | Linux 4.11 | stat64 (139) |
| `lstat64.os` | statx (360) | Linux 4.11 | lstat64 (132) |
| `rename.os` | renameat2 (345) | Linux 3.15 | rename (128) |
| `utimensat.os` | utimensat (310) | Linux 2.6.22 | utimes (271) |

The replacement wrappers are in the [`patches/`](patches/) directory. Each uses
inline SPARC assembly (`ta 0x10` trap) to call the syscall directly, bypassing
the version detection in uclibc-ng.

**fstat64 note**: the direct `fstat64` syscall branch in uclibc-ng's `fstat64.c`
is also gated by `(!__UCLIBC_USE_TIME64__ || LINUX_VERSION_CODE <= 5.1.0)`.
With `__UCLIBC_USE_TIME64__` set and Linux 7.x headers, both branches in
`fstat64.c` are disabled and the object file compiles to nothing — leaving
`__GI_fstat64` undefined. The replacement wrapper provides both `fstat64` and
`__GI_fstat64`.

### What does NOT work

| Approach | Result | Reason |
|---|---|---|
| Debian Wheezy chroot + QEMU sparc32plus | ENOEXEC | Produces `e_machine=0x0012` (SPARC32Plus) |
| Wheezy binary with ELF patch (0x12→0x02) | SIGILL | Wheezy libc.a uses `cas` instructions (SPARC V9) |
| musl-cross-make sparc-linux-musl | Build fails | musl does not support sparc32 |
| Gaisler gcc-7.1 (ReadyNASDuoSparc toolchain) | ENOEXEC inside Wheezy chroot | V7/V8 binary cannot run in sparc32plus chroot |

## Verified hardware

| Device | SoC | CPU | Kernel | Result |
|---|---|---|---|---|
| Netgear ReadyNAS NV+ | IT3107 | SPARC V8 ~400 MHz | Linux 2.6.17.14 | ✅ Works |

Other ReadyNAS models based on the same IT3107 SoC (ReadyNAS Duo, ReadyNAS 1100)
should also work. If you test it on another model, please open an issue or PR.

## Build notes

- `bloom.c` triggers a GCC internal compiler error (ICE) even at `-O1`/`-O2` on
  sparc-buildroot GCC 14. Workaround: `#pragma GCC optimize("O0")` at the top.
- `getrandom()` is not in Linux 2.6.17's glibc. `NO_GETRANDOM=1` suppresses
  git's config flag but the symbol must also be declared and stubbed explicitly
  (see `build.sh` workaround 2).
- `EXTLIBS` must be used (not `LDFLAGS`) for extra libs. git's Makefile places
  `EXTLIBS` after object files on the linker command line, which is required for
  static linking with `-lz -lrt -lpthread -lresolv -lm`.

## License

The patches in `patches/` and `build.sh` are released under the MIT License.
Git itself is GPL-2.0. buildroot and uclibc-ng have their own licenses.
