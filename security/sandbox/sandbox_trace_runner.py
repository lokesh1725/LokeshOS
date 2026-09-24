#!/usr/bin/env python3

import subprocess
from pathlib import Path

# ============================================================
# LokeshOS configuration
# ============================================================

LOKESHOS_ROOT = Path("/home/lokesh/LokeshOS")

ROOTFS = LOKESHOS_ROOT / "security" / "sandbox" / "rootfs"

APP = "/app/test_app.py"

PYTHON = "/usr/bin/python3.13"

APP_USER = "lokeshos-app"
APP_UID = "997"
APP_GID = "985"

# Trace file inside the separate writable /trace mount
TRACE_FILE = "/trace/lokeshos-app.strace"


# ============================================================
# Sandbox launcher
# ============================================================

def run_sandbox():

    if not ROOTFS.exists():
        print("Sandbox rootfs does not exist.")
        print(f"Expected rootfs: {ROOTFS}")
        return

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
            # ------------------------------------------------
            # Make mount propagation private
            # ------------------------------------------------
            "mount --make-rprivate / && "

            # ------------------------------------------------
            # Bind LokeshOS rootfs
            # ------------------------------------------------
            f"mount --bind {ROOTFS} {ROOTFS} && "

            # ------------------------------------------------
            # Make the sandbox system filesystem read-only
            # ------------------------------------------------
            f"mount -o remount,bind,ro {ROOTFS} && "

            # ------------------------------------------------
            # Separate writable trace directory
            # ------------------------------------------------
            f"mount --bind /tmp {ROOTFS}/trace && "

            # ------------------------------------------------
            # Provide /proc
            # ------------------------------------------------
            f"mount --bind /proc {ROOTFS}/proc && "

            # ------------------------------------------------
            # Provide writable application data
            # ------------------------------------------------
            f"mount --bind {ROOTFS}/data/app {ROOTFS}/data/app && "
            f"mount -o remount,bind,rw {ROOTFS}/data/app && "

            # ------------------------------------------------
            # Enter LokeshOS root filesystem
            # ------------------------------------------------
            f"chroot {ROOTFS} "

            # ------------------------------------------------
            # Drop privileges
            # ------------------------------------------------
            f"/usr/bin/setpriv "

            # Remove all capabilities
            f"--bounding-set=-all "

            # Prevent gaining additional privileges
            f"--no-new-privs "

            # Dedicated application UID
            f"--reuid={APP_UID} "

            # Dedicated application GID
            f"--regid={APP_GID} "

            # Remove supplementary groups
            f"--clear-groups "

            # ------------------------------------------------
            # Trace application system calls
            # ------------------------------------------------
            f"/usr/bin/strace "
            f"-f "
            f"-o {TRACE_FILE} "

            # ------------------------------------------------
            # Start application
            # ------------------------------------------------
            f"{PYTHON} {APP}"
        ),
    ]

    # ========================================================
    # Display security configuration
    # ========================================================

    print("=== LokeshOS Sandbox — Syscall Tracing ===")
    print(f"Root filesystem: {ROOTFS}")
    print(f"Application: {APP}")
    print(f"App user: {APP_USER}")
    print(f"App UID: {APP_UID}")
    print(f"App GID: {APP_GID}")
    print()

    print("Mount namespace: enabled")
    print("PID namespace: enabled")
    print("Non-root execution: enabled")
    print("Read-only system filesystem: enabled")
    print("Writable app data: enabled")
    print("Writable trace mount: enabled")
    print("no_new_privs: enabled")
    print("Capability bounding set: empty")
    print("Syscall tracing: enabled")
    print(f"Trace file: {TRACE_FILE}")
    print()

    # ========================================================
    # Execute sandbox
    # ========================================================

    result = subprocess.run(command)

    # ========================================================
    # Trace result
    # ========================================================

    print()
    print("=== Syscall tracing finished ===")
    print(f"Launcher exit code: {result.returncode}")

    trace_path = ROOTFS / "trace" / "lokeshos-app.strace"

    if trace_path.exists():
        print("Trace created successfully.")
        print(f"Trace location: {trace_path}")
    else:
        print("WARNING: Trace file was not created.")


# ============================================================
# Main
# ============================================================

if __name__ == "__main__":
    run_sandbox()
