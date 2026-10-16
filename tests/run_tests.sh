#!/bin/sh
#
# LokeshOS host-side security tests.
#
# These tests verify the pieces the boot flow depends on without needing a
# VM. QEMU boot verification (make run) is a separate, manual step.
#
# Usage: tests/run_tests.sh
# Exit status: 0 when all tests pass, 1 otherwise.

set -u

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
BUILD="$ROOT/build/tests"
PASS=0
FAIL=0
SKIP=0

ok()   { PASS=$((PASS + 1)); printf '  PASS  %s\n' "$1"; }
bad()  { FAIL=$((FAIL + 1)); printf '  FAIL  %s\n' "$1"; }
skip() { SKIP=$((SKIP + 1)); printf '  SKIP  %s\n' "$1"; }

section() { printf '\n== %s ==\n' "$1"; }

mkdir -p "$BUILD"

# ------------------------------------------------------------------
section "Shell syntax"
# ------------------------------------------------------------------
if sh -n "$ROOT/boot/initramfs/init"; then
    ok "boot/initramfs/init parses"
else
    bad "boot/initramfs/init parses"
fi

if sh -n "$ROOT/security/sandbox/sandbox_launch.sh"; then
    ok "security/sandbox/sandbox_launch.sh parses"
else
    bad "security/sandbox/sandbox_launch.sh parses"
fi

# ------------------------------------------------------------------
section "C helpers compile"
# ------------------------------------------------------------------
have_seccomp=0
if [ -f /usr/include/seccomp.h ] || [ -f /usr/local/include/seccomp.h ]; then
    have_seccomp=1
fi

if [ "$have_seccomp" -eq 1 ]; then
    getpid_launcher="$BUILD/getpid_launcher"
    getpid_test="$BUILD/getpid_test"
    policy="$BUILD/seccomp_policy"

    if gcc -O2 -Wall -Wextra -o "$getpid_launcher" \
        "$ROOT/security/seccomp/seccomp_launcher.c" -lseccomp 2>/dev/null; then
        ok "seccomp_launcher.c compiles"
    else
        bad "seccomp_launcher.c compiles"
    fi

    if gcc -O2 -Wall -Wextra -o "$policy" \
        "$ROOT/security/seccomp/seccomp_policy.c" -lseccomp 2>/dev/null; then
        ok "seccomp_policy.c compiles"
    else
        bad "seccomp_policy.c compiles"
    fi

    if gcc -O2 -Wall -Wextra -o "$getpid_test" \
        "$ROOT/security/seccomp/getpid_test.c" 2>/dev/null; then
        ok "getpid_test.c compiles"
    else
        bad "getpid_test.c compiles"
    fi

    # ------------------------------------------------------------------
    section "Seccomp enforcement"
    # ------------------------------------------------------------------
    if [ -x "$getpid_launcher" ] && [ -x "$getpid_test" ]; then
        out=$("$getpid_launcher" "$getpid_test" 2>&1)
        case "$out" in
            *"RESULT: PASS"*) ok "deny-getpid launcher blocks getpid()" ;;
            *)                bad "deny-getpid launcher blocks getpid() -> $out" ;;
        esac
    else
        skip "deny-getpid launcher blocks getpid()"
    fi

    if [ -x "$policy" ]; then
        if "$policy" /bin/true >/dev/null 2>&1; then
            ok "production policy allows /bin/true"
        else
            bad "production policy allows /bin/true"
        fi

        # A syscall that is not on the allowlist must be denied. pipe() is
        # not allowed and always succeeds for an unprivileged user, so an
        # EPERM result proves the seccomp filter (not file permissions).
        cat > "$BUILD/pipe_probe.c" <<'EOF'
#include <unistd.h>
#include <errno.h>
#include <stdio.h>
int main(void) {
    int fds[2];
    if (pipe(fds) != 0 && errno == EPERM) {
        printf("RESULT: PASS\n");
        return 0;
    }
    printf("RESULT: FAIL\n");
    return 1;
}
EOF
        if gcc -O2 -o "$BUILD/pipe_probe" "$BUILD/pipe_probe.c" 2>/dev/null; then
            probe_out=$("$policy" "$BUILD/pipe_probe" 2>&1)
            case "$probe_out" in
                *"RESULT: PASS"*) ok "production policy denies non-allowlisted pipe()" ;;
                *)                bad "production policy denies non-allowlisted pipe() -> $probe_out" ;;
            esac
        else
            skip "production policy denies non-allowlisted pipe()"
        fi
    else
        skip "production policy allows /bin/true"
    fi
else
    skip "seccomp C tests (libseccomp headers not installed)"
fi

# ------------------------------------------------------------------
section "Sandbox rootfs invariants"
# ------------------------------------------------------------------
ROOTFS="$ROOT/security/sandbox/rootfs"
for p in \
    "app/test_app.py" \
    "usr/bin/setpriv" \
    "usr/bin/python3.13" \
    "data/app" \
    "proc" \
    "dev" \
    "security/seccomp"
do
    if [ -e "$ROOTFS/$p" ]; then
        ok "rootfs has /$p"
    else
        bad "rootfs has /$p"
    fi
done

# ------------------------------------------------------------------
section "Initramfs image contents"
# ------------------------------------------------------------------
IMG="$ROOT/boot/initramfs.img"
if [ -f "$IMG" ]; then
    listing=$(gzip -dc "$IMG" 2>/dev/null | cpio -it 2>/dev/null)
    for p in init bin/runas security/auth/pin_auth \
             security/sandbox/sandbox_launch.sh \
             security/sandbox/rootfs/security/seccomp/seccomp_policy \
             security/seccomp/seccomp_launcher \
             security/seccomp/getpid_test
    do
        case "$listing" in
            *"$p"*) ok "initramfs contains $p" ;;
            *)      bad "initramfs contains $p" ;;
        esac
    done
else
    skip "initramfs image not built (run: make)"
fi

# ------------------------------------------------------------------
printf '\n== Summary ==\n'
printf 'PASS=%d FAIL=%d SKIP=%d\n' "$PASS" "$FAIL" "$SKIP"

[ "$FAIL" -eq 0 ]
