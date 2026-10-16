#!/bin/sh
# LokeshOS root-only sandbox launcher.
# Mirrors security/sandbox/sandbox_runner.py for privileged /init use.
# Fail closed: any security setup failure aborts before the application runs.
#
# Does NOT replace the normal authenticated session:
#   PIN → /bin/runas 1000 1000 → lokesh shell

set -eu

die() {
    echo "sandbox_launch: ERROR: $*" >&2
    exit 1
}

# Privileged path only — UID 1000 must never regain root via this tool.
[ "$(id -u)" -eq 0 ] || die "root privileges required (call from privileged /init only)"

# Resolve sandbox rootfs (host development tree or initramfs layout).
if [ -n "${LOKESHOS_SANDBOX_ROOTFS:-}" ]; then
    ROOTFS=$LOKESHOS_SANDBOX_ROOTFS
elif [ -d /security/sandbox/rootfs ]; then
    ROOTFS=/security/sandbox/rootfs
else
    SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
    ROOTFS=$SCRIPT_DIR/rootfs
fi

# Paths inside the chroot (same as sandbox_runner.py).
APP=/app/test_app.py
PYTHON=/usr/bin/python3.13
SECCOMP_LAUNCHER=/security/seccomp/seccomp_policy
APP_UID=997
APP_GID=985

command -v unshare >/dev/null 2>&1 || die "unshare not found"
command -v mount >/dev/null 2>&1 || die "mount not found"
command -v chroot >/dev/null 2>&1 || die "chroot not found"
command -v id >/dev/null 2>&1 || die "id not found"

[ -d "$ROOTFS" ] || die "sandbox rootfs missing: $ROOTFS"
[ -x "$ROOTFS$SECCOMP_LAUNCHER" ] || die "sandbox Seccomp launcher missing: $ROOTFS$SECCOMP_LAUNCHER"
[ -x "$ROOTFS$PYTHON" ] || die "sandbox Python missing: $ROOTFS$PYTHON"
[ -f "$ROOTFS$APP" ] || die "sandbox application missing: $ROOTFS$APP"
[ -x "$ROOTFS/usr/bin/setpriv" ] || die "util-linux setpriv missing in rootfs: $ROOTFS/usr/bin/setpriv"
[ -d "$ROOTFS/proc" ] || die "sandbox /proc mountpoint missing: $ROOTFS/proc"
[ -d "$ROOTFS/dev" ] || die "sandbox /dev mountpoint missing: $ROOTFS/dev"
[ -d "$ROOTFS/data/app" ] || die "sandbox writable data dir missing: $ROOTFS/data/app"

echo "=== LokeshOS Sandbox Launcher ==="
echo "Root filesystem: $ROOTFS"
echo "Application: $APP"
echo "Python: $PYTHON"
echo "Seccomp launcher: $SECCOMP_LAUNCHER"
echo "App UID: $APP_UID"
echo "App GID: $APP_GID"
echo
echo "Mount namespace: enabled"
echo "PID namespace: enabled"
echo "Read-only system filesystem: enabled"
echo "Writable app data: enabled"
echo "no_new_privs: enabled"
echo "Capability bounding set: empty"
echo "Seccomp (sandbox profile): enabled"
echo

# Namespace + mount setup as root, then chroot → setpriv drop → sandbox Seccomp → app.
# Mount flags accept util-linux or BusyBox forms.
# Same security order as sandbox_runner.py (caller must already be root; no sudo).
unshare --mount --pid --fork --mount-proc \
    /bin/busybox env ROOTFS="$ROOTFS" APP_UID="$APP_UID" APP_GID="$APP_GID" \
        SECCOMP_LAUNCHER="$SECCOMP_LAUNCHER" PYTHON="$PYTHON" APP="$APP" \
        sh -c '
    set -eu
    mount --make-rprivate / 2>/dev/null || mount -o remount,rprivate / || exit 1
    mount --bind "$ROOTFS" "$ROOTFS" 2>/dev/null || mount -o bind "$ROOTFS" "$ROOTFS" || exit 1
    mount -o remount,bind,ro "$ROOTFS" || exit 1
    mount --bind /proc "$ROOTFS/proc" 2>/dev/null || mount -o bind /proc "$ROOTFS/proc" || exit 1
    # Provide device nodes (e.g. /dev/urandom) from the already-mounted guest /dev,
    # matching how /proc is supplied. Required for the existing Python runtime.
    [ -d "$ROOTFS/dev" ] || exit 1
    mount --bind /dev "$ROOTFS/dev" 2>/dev/null || mount -o bind /dev "$ROOTFS/dev" || exit 1
    mount --bind "$ROOTFS/data/app" "$ROOTFS/data/app" 2>/dev/null || mount -o bind "$ROOTFS/data/app" "$ROOTFS/data/app" || exit 1
    mount -o remount,bind,rw "$ROOTFS/data/app" || exit 1
    # Give the sandboxed application ownership of its writable data directory.
    chown -R "$APP_UID:$APP_GID" "$ROOTFS/data/app" || exit 1
    exec chroot "$ROOTFS" /usr/bin/setpriv \
        --bounding-set=-all \
        --no-new-privs \
        --reuid="$APP_UID" \
        --regid="$APP_GID" \
        --clear-groups \
        "$SECCOMP_LAUNCHER" "$PYTHON" "$APP"
'

status=$?
echo
echo "=== LokeshOS Sandbox Launcher finished ==="
echo "Launcher exit code: $status"
exit "$status"
