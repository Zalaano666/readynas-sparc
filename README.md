# readynas-sparc

Cross-compiled static binaries and build instructions for the Netgear ReadyNAS
family based on the **Infrant Technologies NEON IT3107 SoC** (plain SPARC V8,
~256 MB RAM, Linux 2.6.17.14, glibc 2.3.2).

Pre-built binaries are available on the [Releases](https://github.com/Zalaano666/readynas-sparc/releases) page.

## Packages

| Package | Version | Notes |
|---|---|---|
| [git](git/) | 2.54.0 | Includes gitweb (patched for Perl 5.8.8) |
| [busybox](busybox/) | 1.37.0 | 402 applets, HTTPS via built-in TLS |

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
syscalls at compile time. Six object files in `libc.a` must be replaced with
direct wrappers before linking any binary:

| Replaced file | Broken syscall | Added in | Direct fallback |
|---|---|---|---|
| `fstat64.os` | statx (360) + TIME64 interaction | Linux 4.11 | fstat64 (63) |
| `stat64.os` | statx (360) | Linux 4.11 | stat64 (139) |
| `lstat64.os` | statx (360) | Linux 4.11 | lstat64 (132) |
| `rename.os` | renameat2 (345) | Linux 3.15 | rename (128) |
| `utimensat.os` | utimensat (310) | Linux 2.6.22 | utimes (271) |
| `clock_gettime.os` | clock_gettime64 (403) + TIME64 struct mismatch | Linux 5.1 | gettimeofday (116) |

The replacement wrappers are in the [`patches/`](patches/) directory. Each uses
inline SPARC assembly (`ta 0x10` trap) to call the syscall directly, bypassing
the version detection in uclibc-ng.

**fstat64 note**: the direct `fstat64` syscall branch in uclibc-ng's `fstat64.c`
is also gated by `(!__UCLIBC_USE_TIME64__ || LINUX_VERSION_CODE <= 5.1.0)`.
With `__UCLIBC_USE_TIME64__` set and Linux 7.x headers, both branches in
`fstat64.c` are disabled and the object file compiles to nothing — leaving
`__GI_fstat64` undefined. The replacement wrapper provides both `fstat64` and
`__GI_fstat64`.

**clock_gettime note**: `clock_gettime64` (403) is unavailable on Linux 2.6.17.
The old `clock_gettime` (263) has a TIME64 struct mismatch on big-endian 32-bit:
uclibc's `struct timespec` has `int64_t tv_sec` but the kernel writes `int32_t`.
The replacement uses `gettimeofday` (116) with a local 32-bit kernel struct to
avoid this. `__GI_utimensat` is also provided in `utimensat.os` as BusyBox
links against this uclibc-internal symbol directly.

**Not all packages need all patches.** git only requires the first five
(`fstat64`, `stat64`, `rename`, `utimensat`). BusyBox additionally requires
`clock_gettime` and the `__GI_utimensat` alias. Applying all six is safe for
both.

### What does NOT work

| Approach | Result | Reason |
|---|---|---|
| Debian Wheezy chroot + QEMU sparc32plus | ENOEXEC | Produces `e_machine=0x0012` (SPARC32Plus) |
| Wheezy binary with ELF patch (0x12→0x02) | SIGILL | Wheezy libc.a uses `cas` instructions (SPARC V9) |
| musl-cross-make sparc-linux-musl | Build fails | musl does not support sparc32 |
| Gaisler gcc-7.1 (ReadyNASDuoSparc toolchain) | ENOEXEC inside Wheezy chroot | V7/V8 binary cannot run in sparc32plus chroot |

## Toolchain setup

Requires an x86-64 Ubuntu/Debian host with ~10 GB free disk space and sudo.
Run once — the toolchain is shared by all packages.

```sh
    bc cpio python3 bison flex libncurses-dev libssl-dev

git clone --depth=1 https://git.buildroot.net/buildroot /root/buildroot

cat > /root/buildroot/sparc_v8_defconfig <<'EOF'
BR2_sparc=y
BR2_sparc_v8=y
BR2_TOOLCHAIN_BUILDROOT_UCLIBC=y
BR2_TOOLCHAIN_BUILDROOT_WCHAR=y
BR2_STATIC_LIBS=y
EOF

cd /root/buildroot
make defconfig BR2_DEFCONFIG=sparc_v8_defconfig
make toolchain -j$(nproc)
# Cross-compiler: /root/buildroot/output/host/bin/sparc-buildroot-linux-uclibc-gcc
```

## Verified hardware

| Device | SoC | CPU | Kernel | Result |
|---|---|---|---|---|
| Netgear ReadyNAS Duo v1 | IT3107 | SPARC V8 ~400 MHz | Linux 2.6.17.14 | ✅ Works |

Other ReadyNAS models based on the same IT3107 SoC (ReadyNAS 1100)
should also work. If you test it on another model, please open an issue or PR.

## Prior work

Pre-built git 2.21.0 (2019) was previously available thanks to
[mfe-/ReadyNASDuoSparc](https://github.com/mfe-/ReadyNASDuoSparc) — the
go-to resource for ReadyNAS SPARC binaries. This repo picks up where that left
off with a newer toolchain and documents the syscall incompatibilities.

## License

The patches and build scripts are released under the MIT License.
Git is GPL-2.0. BusyBox is GPL-2.0. buildroot and uclibc-ng have their own licenses.
