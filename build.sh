#!/bin/sh
# build.sh — cross-compile git 2.54.0 for Netgear ReadyNAS (SPARC V8, Linux 2.6.17)
#
# Run on an x86-64 Ubuntu/Debian host with ~10 GB free disk space.
# Produces: /tmp/git-2.54.0-sparc.tar.gz  (~10 MB, ready to extract on NAS)
#
# Steps:
#   1. Build buildroot cross-compiler (sparc_v8 + uclibc-ng) — ~1–2 hours
#   2. Cross-compile zlib (not in buildroot sysroot)
#   3. Patch libc.a: replace five object files that call ENOSYS syscalls
#   4. Build git 2.54.0 statically
#   5. Pack tarball
#
# Usage:
#   sudo sh build.sh            # full build (step 1 takes ~1–2 hours)
#   sudo sh build.sh git-only   # skip toolchain build (already done)

set -e

GIT_VERSION="2.54.0"
ZLIB_VERSION="1.3.1"
BUILDROOT_DIR="/root/buildroot"
STAGING="/tmp/sparc-staging"
GIT_SRC="/tmp/git-${GIT_VERSION}"
OUTPUT="/tmp/git-${GIT_VERSION}-sparc.tar.gz"

CROSS="${BUILDROOT_DIR}/output/host/bin/sparc-buildroot-linux-uclibc"
UCLIBC_INC="${BUILDROOT_DIR}/output/host/sparc-buildroot-linux-uclibc/sysroot/usr/include"
LIBC="${BUILDROOT_DIR}/output/host/sparc-buildroot-linux-uclibc/sysroot/usr/lib/libc.a"
AR="${BUILDROOT_DIR}/output/host/bin/sparc-buildroot-linux-uclibc-ar"

PATCHES_DIR="$(cd "$(dirname "$0")/patches" && pwd)"

# ── Step 1: buildroot toolchain ───────────────────────────────────────────────
build_toolchain() {
    echo "==> Step 1: buildroot toolchain (~1–2 hours)"
    apt-get update -qq
    apt-get install -y --no-install-recommends \
        build-essential gcc g++ make wget curl git unzip rsync \
        bc cpio python3 python3-pip bison flex libncurses-dev libssl-dev

    if [ ! -d "${BUILDROOT_DIR}" ]; then
        git clone --depth=1 https://git.buildroot.net/buildroot "${BUILDROOT_DIR}"
    fi

    cat > "${BUILDROOT_DIR}/sparc_v8_defconfig" <<'EOF'
BR2_sparc=y
BR2_sparc_v8=y
BR2_TOOLCHAIN_BUILDROOT_UCLIBC=y
BR2_TOOLCHAIN_BUILDROOT_WCHAR=y
BR2_STATIC_LIBS=y
EOF

    cd "${BUILDROOT_DIR}"
    make defconfig BR2_DEFCONFIG=sparc_v8_defconfig
    make toolchain -j"$(nproc)" > /tmp/buildroot-build.log 2>&1
    echo "==> Toolchain ready: ${CROSS}-gcc"
}

# ── Step 2: zlib ──────────────────────────────────────────────────────────────
build_zlib() {
    echo "==> Step 2: cross-compile zlib ${ZLIB_VERSION}"
    mkdir -p "${STAGING}"
    if [ ! -f "/tmp/zlib-${ZLIB_VERSION}.tar.gz" ]; then
        wget -O "/tmp/zlib-${ZLIB_VERSION}.tar.gz" \
            "https://github.com/madler/zlib/releases/download/v${ZLIB_VERSION}/zlib-${ZLIB_VERSION}.tar.gz"
    fi
    rm -rf "/tmp/zlib-${ZLIB_VERSION}"
    tar xzf "/tmp/zlib-${ZLIB_VERSION}.tar.gz" -C /tmp
    cd "/tmp/zlib-${ZLIB_VERSION}"
    CROSS_PREFIX="${CROSS}-" ./configure --prefix="${STAGING}" --static
    make -j"$(nproc)"
    make install
    echo "==> zlib built: $(file ${STAGING}/lib/libz.a | grep -o 'Sparc.*')"
}

# ── Step 3: patch libc.a ──────────────────────────────────────────────────────
patch_libc() {
    echo "==> Step 3: patch libc.a (replace five ENOSYS syscall wrappers)"
    cp "${LIBC}" "${LIBC}.bak"

    for src in fstat64 stat64 rename utimensat; do
        ${CROSS}-gcc -O2 -mcpu=v8 -I"${UCLIBC_INC}" \
            -c "${PATCHES_DIR}/custom_${src}.c" -o "/tmp/${src}.os"
        ${AR} r "${LIBC}" "/tmp/${src}.os"
        echo "   patched ${src}.os"
    done

    # stat64.c contains both stat64 and lstat64 — output named stat64.os covers both
    echo "==> libc.a patched."
}

# ── Step 4: build git ─────────────────────────────────────────────────────────
build_git() {
    echo "==> Step 4: build git ${GIT_VERSION}"
    if [ ! -f "/tmp/git-${GIT_VERSION}.tar.gz" ]; then
        wget -O "/tmp/git-${GIT_VERSION}.tar.gz" \
            "https://mirrors.edge.kernel.org/pub/software/scm/git/git-${GIT_VERSION}.tar.gz"
    fi
    rm -rf "${GIT_SRC}"
    tar xzf "/tmp/git-${GIT_VERSION}.tar.gz" -C /tmp

    cd "${GIT_SRC}"

    # Workaround 1: GCC ICE on bloom.c even at -O2
    sed -i '1s/^/#pragma GCC optimize("O0")\n/' bloom.c

    # Workaround 2: getrandom() not in Linux 2.6.17 glibc
    mkdir -p compat-include/sys
    cat > compat-include/sys/random.h <<'HDR'
#ifndef _SYS_RANDOM_H
#define _SYS_RANDOM_H
#include <sys/types.h>
extern ssize_t getrandom(void *buf, size_t buflen, unsigned int flags);
#endif
HDR
    cat >> wrapper.c <<'STUB'
#include <fcntl.h>
ssize_t getrandom(void *buf, size_t buflen, unsigned int flags) {
    int fd = open("/dev/urandom", O_RDONLY);
    ssize_t n; if (fd < 0) return -1;
    n = read(fd, buf, buflen); close(fd); return n;
}
STUB

    make -j"$(nproc)" prefix=/usr/local \
        CC="${CROSS}-gcc" AR="${CROSS}-ar" RANLIB="${CROSS}-ranlib" \
        CFLAGS="-O2 -I${GIT_SRC}/compat-include -I${STAGING}/include" \
        LDFLAGS="-static -L${STAGING}/lib" \
        EXTLIBS="-lz -lrt -lpthread -lresolv -lm" \
        NO_CURL=1 NO_OPENSSL=1 NO_ICONV=1 NO_GETTEXT=1 NO_GETRANDOM=1 \
        all

    echo "==> Binary: $(file git)"
}

# ── Step 5: pack tarball ──────────────────────────────────────────────────────
pack_tarball() {
    echo "==> Step 5: pack tarball"
    cd "${GIT_SRC}"
    rm -rf /tmp/git-br-build
    make -j"$(nproc)" prefix=/usr/local DESTDIR=/tmp/git-br-build \
        CC="${CROSS}-gcc" AR="${CROSS}-ar" RANLIB="${CROSS}-ranlib" \
        CFLAGS="-O2 -I${GIT_SRC}/compat-include -I${STAGING}/include" \
        LDFLAGS="-static -L${STAGING}/lib" \
        EXTLIBS="-lz -lrt -lpthread -lresolv -lm" \
        NO_CURL=1 NO_OPENSSL=1 NO_ICONV=1 NO_GETTEXT=1 NO_GETRANDOM=1 \
        install 2>/dev/null

    cp gitweb/gitweb.cgi /tmp/git-br-build/usr/local/share/gitweb/
    cp -r gitweb/static  /tmp/git-br-build/usr/local/share/gitweb/
    tar czf "${OUTPUT}" -C /tmp/git-br-build .
    ls -lh "${OUTPUT}"
    echo "==> Done."
    echo ""
    echo "Deploy to NAS:"
    echo "  scp ${OUTPUT} root@<NAS_IP>:/tmp/"
    echo "  ssh root@<NAS_IP> 'tar xzf /tmp/git-${GIT_VERSION}-sparc.tar.gz -C / && git --version'"
    echo ""
    echo "First-time NAS setup (safe.directory for root and git user):"
    echo "  ssh root@<NAS_IP> 'for h in /root /c/home/git; do"
    echo "    printf \"[safe]\n    directory = *\n\" > \$h/.gitconfig"
    echo "    chown \$(stat -c \"%u:%g\" \$h) \$h/.gitconfig; done'"
}

# ── Main ──────────────────────────────────────────────────────────────────────
case "${1:-full}" in
    full)
        build_toolchain
        build_zlib
        patch_libc
        build_git
        pack_tarball
        ;;
    git-only)
        build_zlib
        patch_libc
        build_git
        pack_tarball
        ;;
    *)
        echo "Usage: sudo sh build.sh [full|git-only]"
        exit 1
        ;;
esac
