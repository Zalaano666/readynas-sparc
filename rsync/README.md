# rsync 3.4.1 for ReadyNAS Duo V1 (SPARC)

See the [top-level README](../README.md) for toolchain setup and libc.a patching.

## Quick install (pre-built binary)

Download `rsync-3.4.1-sparc` from the [Releases](https://github.com/Zalaano666/readynas-sparc/releases) page:

```sh
scp rsync-3.4.1-sparc root@<NAS_IP>:/tmp/rsync
ssh root@<NAS_IP> 'chmod +x /tmp/rsync && cp /tmp/rsync /usr/local/bin/rsync && rsync --version'
```

## Build from source

```sh
sudo sh rsync/build.sh
```

Output: `/tmp/rsync-3.4.1-sparc`

## Notes

- Built without xxhash, zstd, lz4, openssl — uses MD4/MD5 and zlib (protocol 32)
- Replaces system rsync 3.0.9 in `/usr/local/bin/` — original in `/usr/bin/rsync` is untouched
