#!/bin/sh
# busybox/build.sh — cross-compile BusyBox 1.37.0 for Netgear ReadyNAS (SPARC V8, Linux 2.6.17)
#
# Run on an x86-64 Ubuntu/Debian host with the buildroot toolchain already built.
# All six libc.a patches in ../patches/ must be applied before running this script.
# See git/build.sh for toolchain setup and libc.a patching instructions.
#
# Output: /tmp/busybox  (copy to /usr/local/bin/busybox on NAS)
#
# Usage:
#   sudo sh busybox/build.sh

set -e

BUSYBOX_VERSION="1.37.0"
BUILDROOT_DIR="/root/buildroot"

CROSS="${BUILDROOT_DIR}/output/host/bin/sparc-buildroot-linux-uclibc"
PATCHES_DIR="$(cd "$(dirname "$0")/../patches" && pwd)"
LIBC="${BUILDROOT_DIR}/output/host/sparc-buildroot-linux-uclibc/sysroot/usr/lib/libc.a"
AR="${BUILDROOT_DIR}/output/host/bin/sparc-buildroot-linux-uclibc-ar"
UCLIBC_INC="${BUILDROOT_DIR}/output/host/sparc-buildroot-linux-uclibc/sysroot/usr/include"

# ── Step 1: apply libc.a patches ─────────────────────────────────────────────
patch_libc() {
    echo "==> Patching libc.a (six syscall wrappers)"
    cp "${LIBC}" "${LIBC}.bak"
    for src in fstat64 stat64 rename utimensat clock_gettime; do
        ${CROSS}-gcc -O2 -mcpu=v8 -I"${UCLIBC_INC}" \
            -c "${PATCHES_DIR}/custom_${src}.c" -o "/tmp/${src}.os"
        ${AR} r "${LIBC}" "/tmp/${src}.os"
        echo "   patched ${src}.os"
    done
    echo "==> libc.a patched."
}

# ── Step 2: build BusyBox ─────────────────────────────────────────────────────
build_busybox() {
    echo "==> Downloading BusyBox ${BUSYBOX_VERSION}"
    if [ ! -f "/tmp/busybox-${BUSYBOX_VERSION}.tar.bz2" ]; then
        wget -O "/tmp/busybox-${BUSYBOX_VERSION}.tar.bz2" \
            "https://busybox.net/downloads/busybox-${BUSYBOX_VERSION}.tar.bz2"
    fi
    rm -rf "/tmp/busybox-${BUSYBOX_VERSION}"
    tar xjf "/tmp/busybox-${BUSYBOX_VERSION}.tar.bz2" -C /tmp
    cd "/tmp/busybox-${BUSYBOX_VERSION}"

    echo "==> Configuring"
    make defconfig ARCH=sparc
    sed -i 's/# CONFIG_STATIC is not set/CONFIG_STATIC=y/' .config
    sed -i 's/CONFIG_CROSS_COMPILER_PREFIX=""/CONFIG_CROSS_COMPILER_PREFIX="sparc-buildroot-linux-uclibc-"/' .config
    sed -i 's/CONFIG_EXTRA_CFLAGS=""/CONFIG_EXTRA_CFLAGS="-mcpu=v8"/' .config
    # SHA-NI is x86-only — does not compile on SPARC
    sed -i 's/CONFIG_SHA1_HWACCEL=y/# CONFIG_SHA1_HWACCEL is not set/' .config
    sed -i 's/CONFIG_SHA256_HWACCEL=y/# CONFIG_SHA256_HWACCEL is not set/' .config
    # tc uses CBQ kernel headers not present in uclibc-ng sysroot
    sed -i 's/^CONFIG_TC=y/# CONFIG_TC is not set/' .config

    echo "==> Building"
    PATH="${BUILDROOT_DIR}/output/host/bin:${PATH}" make -j"$(nproc)"

    cp busybox /tmp/busybox
    echo "==> Binary: $(file /tmp/busybox)"
    echo ""
    echo "Deploy to NAS:"
    echo "  scp /tmp/busybox root@<NAS_IP>:/tmp/busybox"
    echo "  ssh root@<NAS_IP> 'chmod +x /tmp/busybox && cp /tmp/busybox /usr/local/bin/busybox && /usr/local/bin/busybox --install -s /usr/local/bin/'"
}

patch_libc
build_busybox
