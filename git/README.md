# git 2.54.0 for ReadyNAS SPARC V8

See the [top-level README](../README.md) for toolchain setup and libc.a patching.
Apply all patches in [`../patches/`](../patches/) before building.

## Quick install (pre-built binary)

Download `git-2.54.0-sparc.tar.gz` from the [Releases](https://github.com/Zalaano666/readynas-sparc/releases) page:

```sh
scp git-2.54.0-sparc.tar.gz root@<NAS_IP>:/tmp/
ssh root@<NAS_IP> 'tar xzf /tmp/git-2.54.0-sparc.tar.gz -C / && git --version'
```

First-time setup:

```sh
ssh root@<NAS_IP> '
for h in /root /c/home/git; do
  printf "[safe]\n    directory = *\n" > $h/.gitconfig
  chown $(stat -c "%u:%g" $h) $h/.gitconfig
done'
```

## Build from source

```sh
sudo sh git/build.sh          # full build including toolchain (~1-2 hours)
sudo sh git/build.sh git-only # skip toolchain (already built)
```

Output: `/tmp/git-2.54.0-sparc.tar.gz`

## gitweb

git 2.54.0's `gitweb.cgi` requires Perl 5.26 — the NAS has Perl 5.8.8.
[`gitweb.cgi`](gitweb.cgi) is git 2.21.0's `gitweb.perl` patched for Perl 5.8.8
with all build variables substituted for NAS paths.

```sh
scp git/gitweb.cgi root@<NAS_IP>:/usr/local/share/gitweb/gitweb.cgi
ssh root@<NAS_IP> 'chmod +x /usr/local/share/gitweb/gitweb.cgi'
```

## Build notes

- `bloom.c` triggers a GCC ICE at `-O1`/`-O2` — workaround: `#pragma GCC optimize("O0")`
- `getrandom()` not in Linux 2.6.17 glibc — must be declared and stubbed (see `build.sh`)
- Use `EXTLIBS` (not `LDFLAGS`) for extra libs — git's Makefile places them after object files
