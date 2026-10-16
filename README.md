# LokeshOS

A small, security-focused operating system built incrementally on Ubuntu:
LUKS2 encrypted storage, PIN authentication, a custom initramfs, a
namespace-based application sandbox, and seccomp syscall filtering.

The full engineering record lives in [`LokeshOS.md`](LokeshOS.md).

## Layout

```text
boot/                 custom initramfs tree + generated boot images
kernel/               Linux kernel source/build tree (gitignored)
security/
  auth/               PIN authentication + privilege-drop helper (runas)
  sandbox/            sandbox runner, launcher, chroot rootfs, test app
  seccomp/            seccomp launcher + production allowlist policy
ui/                   branding assets
tests/                host-side security tests
Makefile              reproducible build
```

## Build

```bash
make            # compile C helpers and pack boot/initramfs.img
make kernel     # copy the built kernel image to boot/vmlinuz
make image      # kernel + initramfs
make iso        # build boot/lokeshos.iso (bootable ISO, BIOS)
```

The build stages everything under `build/` and never mutates the source tree.
`make iso` bootstraps GRUB/xorriso into `build/iso-tools` if the host lacks
them (no root required).

## Run

```bash
make run        # boot kernel + initramfs directly in QEMU (serial)
make run-iso    # boot the ISO in QEMU
```

To boot the ISO in a VM directly:

```bash
qemu-system-x86_64 -m 1024 -cdrom boot/lokeshos.iso -nographic -boot d
```

Kernel command line options:

- `lokeshos.nosandbox` — skip the sandbox application path.
- `lokeshos.shell` — skip authentication (development only).

## Test

```bash
make test       # host-side security tests (no VM)
make check      # gcc -fsyntax-only on all C sources
```

## Security model

- PIN authentication before any shell; fails closed after three attempts.
- Unprivileged shell at UID/GID `1000` (`lokesh`).
- Sandboxed apps run as UID `997`/GID `985` with:
  - mount + PID namespaces,
  - `no_new_privs`,
  - an empty capability bounding set,
  - a read-only system filesystem,
  - a writable private data directory,
  - a seccomp allowlist (`security/seccomp/seccomp_policy.c`, default `EPERM`).

## Notes

LokeshOS is a research/learning project. The authentication PIN is a
development placeholder and secrets (`security/auth/pin.hash`) are gitignored.
