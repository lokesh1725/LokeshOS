#!/bin/sh
#
# LokeshOS bootable ISO builder.
#
# Produces a BIOS-bootable (El Torito) ISO containing the kernel, initramfs
# and a GRUB menu. Works without root: if the required GRUB/xorriso pieces
# are not installed, they are downloaded and extracted into build/iso-tools.
#
# Usage: scripts/mkiso.sh [output.iso]
# Default output: boot/lokeshos.iso

set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
BUILD="$ROOT/build"
TOOLS="$BUILD/iso-tools"
WORK="${BUILD}/iso"
OUT="${1:-$ROOT/boot/lokeshos.iso}"

KERNEL="$ROOT/boot/vmlinuz"
INITRD="$ROOT/boot/initramfs.img"

fail() { echo "mkiso: ERROR: $*" >&2; exit 1; }

[ -f "$KERNEL" ] || { echo "missing $KERNEL (run: make kernel)"; exit 1; }
[ -f "$INITRD" ] || { echo "missing $INITRD (run: make)"; exit 1; }

# ---------------------------------------------------------------
# Locate or bootstrap GRUB + xorriso tooling (no root required).
# ---------------------------------------------------------------
GRUB_BASE="${GRUB_BASE:-/usr/lib/grub}"
I386_DIR="$GRUB_BASE/i386-pc"
BOOTSTRAPPED=0

if [ ! -d "$I386_DIR" ] || ! command -v xorriso >/dev/null 2>&1; then
    echo "  ISO    bootstrapping GRUB/xorriso into build/iso-tools"
    mkdir -p "$TOOLS"
    (
        cd "$TOOLS"
        for p in xorriso mtools grub-pc-bin grub-common \
                 libisoburn1t64 libisoburn1 \
                 libisofs6t64 libisofs6 \
                 libburn4t64 libburn4 \
                 libjte2 libjte1; do
            apt-get download "$p" >/dev/null 2>&1 || true
        done
    )
    for d in "$TOOLS"/*.deb; do
        [ -f "$d" ] || continue
        dpkg-deb -x "$d" "$TOOLS" >/dev/null 2>&1 || true
    done
    TOOLS_USR="$TOOLS/usr"
    export LD_LIBRARY_PATH="$TOOLS_USR/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
    export PATH="$TOOLS_USR/bin:$TOOLS_USR/sbin:$PATH"
    BOOTSTRAPPED=1
    if [ -d "$TOOLS_USR/lib/grub/i386-pc" ]; then
        I386_DIR="$TOOLS_USR/lib/grub/i386-pc"
    fi
fi

command -v grub-mkimage >/dev/null 2>&1 || { echo "grub-mkimage not found"; exit 1; }
command -v xorriso >/dev/null 2>&1 || { echo "xorriso not found and bootstrap failed"; exit 1; }
[ -f "$I386_DIR/cdboot.img" ] || { echo "GRUB i386-pc modules not found in $I386_DIR"; exit 1; }

# ---------------------------------------------------------------
# Build the BIOS El Torito core image.
# ---------------------------------------------------------------
echo "  ISO    building GRUB BIOS core image"
rm -rf "$WORK"
mkdir -p "$WORK/isoroot/boot/grub/i386-pc"

grub-mkimage -O i386-pc -d "$I386_DIR" -p /boot/grub \
    -o "$WORK/core.img" \
    iso9660 biosdisk normal linux configfile search search_fs_file echo

cat "$I386_DIR/cdboot.img" "$WORK/core.img" > "$WORK/eltorito.img"
cp "$WORK/eltorito.img" "$WORK/isoroot/boot/grub/i386-pc/eltorito.img"

# ---------------------------------------------------------------
# Stage the ISO tree.
# ---------------------------------------------------------------
echo "  ISO    staging kernel + initramfs"
cp "$KERNEL" "$WORK/isoroot/boot/vmlinuz"
cp "$INITRD" "$WORK/isoroot/boot/initramfs.img"

cat > "$WORK/isoroot/boot/grub/grub.cfg" <<'EOF'
set timeout=5
set default=0

menuentry "LokeshOS" {
    linux  /boot/vmlinuz console=ttyS0 panic=1
    initrd /boot/initramfs.img
}

menuentry "LokeshOS (no sandbox)" {
    linux  /boot/vmlinuz console=ttyS0 panic=1 lokeshos.nosandbox
    initrd /boot/initramfs.img
}

menuentry "LokeshOS (recovery shell)" {
    linux  /boot/vmlinuz console=ttyS0 panic=1 lokeshos.shell
    initrd /boot/initramfs.img
}
EOF

# ---------------------------------------------------------------
# Assemble the ISO.
# ---------------------------------------------------------------
echo "  ISO    assembling $OUT"
mkdir -p "$(dirname "$OUT")"
xorriso -as mkisofs -o "$OUT" \
    -V "LokeshOS" \
    -b boot/grub/i386-pc/eltorito.img \
    -no-emul-boot -boot-load-size 4 -boot-info-table \
    -c boot/boot.cat \
    "$WORK/isoroot" >/dev/null 2>&1

echo "  OK     $OUT ($(du -h "$OUT" | cut -f1))"
