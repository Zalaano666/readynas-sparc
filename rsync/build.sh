#!/bin/sh
# rsync/build.sh — cross-compile rsync 3.4.1 for Netgear ReadyNAS (SPARC V8, Linux 2.6.17)
#
# Requires: buildroot toolchain + zlib in /tmp/sparc-staging (see git/build.sh)
# libc.a patches are NOT required for rsync.
#
# Output: /tmp/rsync-3.4.1-sparc

set -e

RSYNC_VERSION="3.4.1"
BUILDROOT_DIR="/root/buildroot"
STAGING="/tmp/sparc-staging"

CROSS="${BUILDROOT_DIR}/output/host/bin/sparc-buildroot-linux-uclibc"

if [ ! -f "/tmp/rsync-${RSYNC_VERSION}.tar.gz" ]; then
    curl -L -o "/tmp/rsync-${RSYNC_VERSION}.tar.gz" \
        "https://github.com/RsyncProject/rsync/releases/download/v${RSYNC_VERSION}/rsync-${RSYNC_VERSION}.tar.gz"
fi

rm -rf "/tmp/rsync-${RSYNC_VERSION}"
tar xzf "/tmp/rsync-${RSYNC_VERSION}.tar.gz" -C /tmp
cd "/tmp/rsync-${RSYNC_VERSION}"

PATH="${BUILDROOT_DIR}/output/host/bin:${PATH}" \
./configure --host=sparc-buildroot-linux-uclibc \
    --disable-xxhash --disable-zstd --disable-lz4 \
    --disable-openssl --disable-md2man \
    CC="${CROSS}-gcc" \
    CFLAGS="-O2 -mcpu=v8 -I${STAGING}/include" \
    LDFLAGS="-static -L${STAGING}/lib"

PATH="${BUILDROOT_DIR}/output/host/bin:${PATH}" make -j"$(nproc)"
"${CROSS}-strip" rsync
cp rsync "/tmp/rsync-${RSYNC_VERSION}-sparc"

echo "==> Binary: $(file /tmp/rsync-${RSYNC_VERSION}-sparc)"
echo ""
echo "Deploy to NAS:"
echo "  scp /tmp/rsync-${RSYNC_VERSION}-sparc root@<NAS_IP>:/tmp/rsync"
echo "  ssh root@<NAS_IP> 'chmod +x /tmp/rsync && cp /tmp/rsync /usr/local/bin/rsync'"
