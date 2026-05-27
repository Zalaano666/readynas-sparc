# BusyBox 1.37.0 for ReadyNAS SPARC V8

See the [top-level README](../README.md) for toolchain setup and libc.a patching.
Apply **all six** patches in [`../patches/`](../patches/) before building —
BusyBox additionally requires `clock_gettime` and the `__GI_utimensat` alias.

## Quick install (pre-built binary)

Download `busybox-1.37.0-sparc` from the [Releases](https://github.com/Zalaano666/readynas-sparc/releases) page:

```sh
scp busybox-1.37.0-sparc root@<NAS_IP>:/tmp/busybox
ssh root@<NAS_IP> 'chmod +x /tmp/busybox && cp /tmp/busybox /usr/local/bin/busybox && /usr/local/bin/busybox --install -s /usr/local/bin/'
```

Installs to `/usr/local/bin/` — does not touch the system BusyBox in `/bin/`.

## Build from source

```sh
sudo sh busybox/build.sh
```

Output: `/tmp/busybox`

## Notes

- HTTPS works via the built-in TLS (no external OpenSSL needed)
- 402 applets
- `find -ls` is not supported — use `find ... -exec ls -la {} \;` instead
