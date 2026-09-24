#!/usr/bin/env python3

import os
import subprocess
from pathlib import Path

# ============================================================
# LokeshOS Sandbox Configuration
# ============================================================

REAL_USER = os.environ.get("SUDO_USER") or os.environ.get("USER")

if REAL_USER:
    LOKESHOS_ROOT = Path("/home") / REAL_USER / "LokeshOS"
else:
    LOKESHOS_ROOT = Path("/home/lokesh/LokeshOS")

ROOTFS = LOKESHOS_ROOT / "security" / "sandbox" / "rootfs"

# These paths are INSIDE the chroot.
APP = "/app/test_app.py"
PYTHON = "/usr/bin/python3.13"

# Seccomp launcher path INSIDE the chroot.
SECCOMP_LAUNCHER = "/security/seccomp/seccomp_profile_test"

APP_USER = "lokeshos-app"
APP_UID = "997"
APP_GID = "985"


def run_sandbox():

    # --------------------------------------------------------
    # Host-side checks
    # --------------------------------------------------------

    if not ROOTFS.exists():
        print("Sandbox rootfs does not exist.")
        print(f"Expected: {ROOTFS}")
        return

    host_seccomp = (
        ROOTFS
        / "security"
        / "seccomp"
        / "seccomp_profile_test"
    )

    if not host_seccomp.exists():
        print("Seccomp launcher does not exist inside rootfs.")
        print(f"Expected: {host_seccomp}")
        return

    # --------------------------------------------------------
    # Sandbox command
    # --------------------------------------------------------

    command = [
        "sudo",
        "unshare",
        "--mount",
        "--pid",
        "--fork",
        "--mount-proc",
        "sh",
        "-c",
        (
            # Private mount namespace
            "mount --make-rprivate / && "

            # Make rootfs available in the namespace
            f"mount --bind {ROOTFS} {ROOTFS} && "

            # System filesystem read-only
            f"mount -o remount,bind,ro {ROOTFS} && "

            # PID namespace /proc
            f"mount --bind /proc {ROOTFS}/proc && "

            # Writable application data
            f"mount --bind {ROOTFS}/data/app {ROOTFS}/data/app && "
            f"mount -o remount,bind,rw {ROOTFS}/data/app && "

            # Enter rootfs
            f"chroot {ROOTFS} "

            # Drop privileges
            f"/usr/bin/setpriv "
            f"--bounding-set=-all "
            f"--no-new-privs "
            f"--reuid={APP_UID} "
            f"--regid={APP_GID} "
            f"--clear-groups "

            # IMPORTANT:
            # This path is relative to the chroot.
            f"{SECCOMP_LAUNCHER} "

            # Seccomp launcher executes Python.
            f"{PYTHON} {APP}"
        ),
    ]

    # --------------------------------------------------------
    # Display configuration
    # --------------------------------------------------------

    print("=== LokeshOS Sandbox + Seccomp ===")
    print(f"Root filesystem: {ROOTFS}")
    print(f"Application: {APP}")
    print(f"Python: {PYTHON}")
    print(f"Seccomp launcher: {SECCOMP_LAUNCHER}")
    print(f"App user: {APP_USER}")
    print(f"App UID: {APP_UID}")
    print(f"App GID: {APP_GID}")
    print()
    print("Mount namespace: enabled")
    print("PID namespace: enabled")
    print("Non-root execution: enabled")
    print("Read-only system filesystem: enabled")
    print("Writable app data: enabled")
    print("no_new_privs: enabled")
    print("Capability bounding set: empty")
    print("Seccomp syscall filtering: enabled")
    print()

    # --------------------------------------------------------
    # Start sandbox
    # --------------------------------------------------------

    result = subprocess.run(command)

    # --------------------------------------------------------
    # Result
    # --------------------------------------------------------

    print()
    print("=== LokeshOS Sandbox + Seccomp finished ===")
    print(f"Launcher exit code: {result.returncode}")


if __name__ == "__main__":
    run_sandbox()