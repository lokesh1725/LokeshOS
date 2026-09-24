# LokeshOS — End-to-End Development Documentation

## Project

- **Project:** LokeshOS
- **Developer:** Lokeshwaran K.
- **Working directory:** `~/LokeshOS`
- **Architecture:** x86_64
- **GitHub:** `https://github.com/lokesh1725/LokeshOS`
- **Branch:** `main`

---

## 1. Overall Goal

LokeshOS is a security-focused operating-system development project built incrementally on Ubuntu.

The development path has included:

1. Secure encrypted storage using LUKS2.
2. PIN authentication using Python and bcrypt.
3. Authentication components inside initramfs.
4. A custom initramfs tree.
5. Linux kernel integration.
6. An application sandbox.
7. Mount and PID namespace isolation.
8. Non-root application execution.
9. `no_new_privs`.
10. Empty capability bounding set.
11. Read-only sandbox system filesystem.
12. Writable private application data.
13. Host-home isolation testing.
14. Seccomp syscall filtering.
15. Syscall tracing.
16. Git/GitHub version control.

The current major direction is to continue from the working security prototype toward deeper boot/initramfs integration and a reproducible bootable LokeshOS environment.

---

# 2. Development Environment

Main project directory:

```bash
~/LokeshOS
```

Enter it:

```bash
cd ~/LokeshOS
```

Check:

```bash
pwd
```

Expected:

```text
/home/lokesh/LokeshOS
```

---

# 3. Project Structure

The important current areas are:

```text
LokeshOS/
├── .gitignore
├── boot/
│   └── initramfs/
│       ├── bin/
│       ├── etc/
│       ├── lib/
│       ├── lib64/
│       ├── security/
│       └── init
├── security/
│   ├── auth/
│   ├── sandbox/
│   │   ├── apps/
│   │   ├── data/
│   │   ├── rootfs/
│   │   ├── sandbox_runner.py
│   │   └── sandbox_trace_runner.py
│   └── seccomp/
├── ui/
│   └── branding/
│       └── logo/
└── kernel/
    └── linux/
        └── arch/x86/boot/bzImage
```

---

# 4. LUKS2 Secure Storage Foundation

A secure vault was created using LUKS2.

Check cryptsetup:

```bash
cryptsetup --version
```

Format the encrypted container:

```bash
sudo cryptsetup luksFormat --type luks2 secure-vault.img
```

Inspect LUKS metadata:

```bash
sudo cryptsetup luksDump secure-vault.img
```

Open it:

```bash
sudo cryptsetup open secure-vault.img securevault
```

Create an ext4 filesystem:

```bash
sudo mkfs.ext4 /dev/mapper/securevault
```

The secure-storage work was initially developed under `SecureOS` and later the project directory was renamed:

```bash
mv ~/SecureOS ~/LokeshOS
```

The mapped vault was later worked with as:

```text
/dev/mapper/lokeshvault
```

The LUKS layer is part of the project's security foundation.

---

# 5. PIN Authentication

Authentication was implemented under:

```text
security/auth/
```

Important files:

```text
security/auth/auth.py
security/auth/pin_auth.c
security/auth/pin_auth
security/auth/pin.hash
```

The Python implementation uses bcrypt:

```python
#!/usr/bin/env python3

import bcrypt
from pathlib import Path

HASH_FILE = Path(__file__).parent / "pin.hash"
MAX_ATTEMPTS = 3


def load_pin_hash():
    return HASH_FILE.read_bytes().strip()


def authenticate():
    pin_hash = load_pin_hash()
    attempts = 0

    while attempts < MAX_ATTEMPTS:
        pin = input("Enter LokeshOS PIN: ").encode()

        if bcrypt.checkpw(pin, pin_hash):
            print("Authentication successful.")
            return True

        attempts += 1
        remaining = MAX_ATTEMPTS - attempts

        print("Authentication failed.")

        if remaining > 0:
            print(f"Attempts remaining: {remaining}")

    print("Too many failed attempts. Access locked.")
    return False


if __name__ == "__main__":
    authenticate()
```

Run it:

```bash
python3 security/auth/auth.py
```

Testing included a successful PIN and an incorrect PIN. The authentication system allows three failed attempts during one run.

---

# 6. bcrypt Installation

bcrypt was installed with:

```bash
sudo apt install python3-bcrypt
```

Authentication hash files were kept private.

Check permissions:

```bash
ls -lh security/auth/pin.hash
ls -lh boot/initramfs/security/auth/pin.hash
```

The hash files used restrictive permissions:

```text
-rw-------
```

**Do not place the actual PIN, hash, GitHub token, password, or other secrets into this documentation.**

---

# 7. Initramfs Authentication

Authentication components were also placed into:

```text
boot/initramfs/security/auth/
```

Files include:

```text
boot/initramfs/security/auth/auth.py
boot/initramfs/security/auth/pin_auth
boot/initramfs/security/auth/pin.hash
```

This provides an authentication/security layer available in the early userspace environment.

---

# 8. Initramfs

The initramfs tree is under:

```text
boot/initramfs/
```

Important files include:

```text
boot/initramfs/init
boot/initramfs/bin/busybox
boot/initramfs/bin/dash
boot/initramfs/etc/passwd
boot/initramfs/etc/group
boot/initramfs/lib/
boot/initramfs/lib64/
boot/initramfs/security/
```

The init script was created to establish the early userspace environment, mount required virtual filesystems, display boot status, and provide a shell.

The initramfs was progressively populated with required commands, libraries, authentication components, and security tools.

---

# 9. Linux Kernel

A Linux kernel image exists at:

```text
kernel/linux/arch/x86/boot/bzImage
```

The kernel image was approximately 15 MB during development.

The kernel/initramfs work is intended to become the boot foundation for LokeshOS.

---

# 10. Sandbox

The sandbox implementation is under:

```text
security/sandbox/
```

Main files:

```text
security/sandbox/apps/test_app.py
security/sandbox/sandbox_runner.py
security/sandbox/sandbox_trace_runner.py
```

Sandbox root filesystem:

```text
security/sandbox/rootfs/
```

Application source:

```text
security/sandbox/apps/test_app.py
```

Application inside rootfs:

```text
security/sandbox/rootfs/app/test_app.py
```

---

# 11. Sandbox Application Identity

The sandbox uses a dedicated non-root identity:

```text
User: lokeshos-app
UID: 997
GID: 985
```

The runner uses:

```text
--reuid=997
--regid=985
--clear-groups
```

This means the application is not intended to run as root.

---

# 12. Linux Namespaces

The sandbox uses:

```bash
unshare --mount --pid --fork --mount-proc
```

The design includes:

- Mount namespace.
- PID namespace.
- Private mount propagation.
- Separate sandbox root filesystem.
- `/proc` inside the sandbox.

Mount propagation is made private with:

```bash
mount --make-rprivate /
```

The rootfs is bind-mounted:

```bash
mount --bind ROOTFS ROOTFS
```

The sandbox system filesystem is remounted read-only:

```bash
mount -o remount,bind,ro ROOTFS
```

---

# 13. `/proc` Mount

The sandbox initially failed because its `/proc` mount point did not exist.

The fix was:

```bash
sudo mkdir -p security/sandbox/rootfs/proc
```

Check:

```bash
ls -ld security/sandbox/rootfs/proc
```

---

# 14. Private Application Data

Writable application data is located at:

```text
security/sandbox/rootfs/data/app
```

The runner bind-mounts the application-data directory and remounts it writable.

The application uses:

```text
/data/app
```

for private writable data.

The successful test created:

```text
/data/app/sandbox-write-test.txt
```

This demonstrates the intended separation:

```text
System filesystem -> read-only
Application data  -> writable
```

---

# 15. Trace Directory

A trace mount point was created:

```bash
sudo mkdir -p security/sandbox/rootfs/trace
```

Check:

```bash
ls -ld security/sandbox/rootfs/trace
```

The tracing runner uses this area for syscall traces.

---

# 16. Python Runtime Inside the Sandbox

The sandbox uses:

```text
/usr/bin/python3.13
```

At first, Python did not exist inside the chroot.

Check host Python:

```bash
ls -l /usr/bin/python3.13
```

Python was copied into the rootfs:

```bash
sudo mkdir -p security/sandbox/rootfs/usr/bin
sudo cp /usr/bin/python3.13 security/sandbox/rootfs/usr/bin/
```

The Python standard library was copied:

```bash
sudo mkdir -p security/sandbox/rootfs/usr/lib

sudo cp -a /usr/lib/python3.13 security/sandbox/rootfs/usr/lib/
```

The Python standard library occupied approximately 100 MB.

---

# 17. Runtime Dependencies

Python dependencies were inspected with:

```bash
ldd /usr/bin/python3.13
```

Important dependencies included:

```text
libm.so.6
libz.so.1
libexpat.so.1
libc.so.6
/lib64/ld-linux-x86-64.so.2
```

The dynamic loader was added:

```bash
sudo mkdir -p security/sandbox/rootfs/lib64

sudo cp /lib64/ld-linux-x86-64.so.2 security/sandbox/rootfs/lib64/ld-linux-x86-64.so.2
```

Missing Python libraries were added:

```bash
sudo mkdir -p security/sandbox/rootfs/lib/x86_64-linux-gnu

sudo cp -L /lib/x86_64-linux-gnu/libm.so.6 security/sandbox/rootfs/lib/x86_64-linux-gnu/

sudo cp -L /lib/x86_64-linux-gnu/libz.so.1 security/sandbox/rootfs/lib/x86_64-linux-gnu/

sudo cp -L /lib/x86_64-linux-gnu/libexpat.so.1 security/sandbox/rootfs/lib/x86_64-linux-gnu/
```

---

# 18. `setpriv`

The sandbox uses `/usr/bin/setpriv`.

Host location:

```bash
which setpriv
```

Result:

```text
/usr/bin/setpriv
```

It was copied:

```bash
sudo mkdir -p security/sandbox/rootfs/usr/bin
sudo cp /usr/bin/setpriv security/sandbox/rootfs/usr/bin/
```

Its dependency was added:

```bash
sudo cp /lib/x86_64-linux-gnu/libcap-ng.so.0 security/sandbox/rootfs/lib/x86_64-linux-gnu/
```

This fixed the initial missing-`setpriv` stage, after which the next missing runtime component could be identified.

---

# 19. Test Application

The application is:

```text
security/sandbox/apps/test_app.py
```

It checks:

- PID.
- UID.
- GID.
- `NoNewPrivs`.
- Root filesystem visibility.
- Private application data.
- Host home visibility.
- System filesystem write protection.
- Private application-data write access.

Important checks include:

```python
os.getpid()
os.getuid()
os.getgid()
```

and:

```text
/proc/self/status
```

for:

```text
NoNewPrivs:
```

---

# 20. Host Home Isolation

The test checks:

```text
/home/lokesh
```

inside the sandbox.

The successful result was:

```text
Host home directory is NOT visible. ✅
```

This verifies that the sandbox root does not expose the host home directory through the tested filesystem view.

---

# 21. Read-Only System Filesystem

The test application tries to write:

```text
/app/system-write-test.txt
```

The successful result was:

```text
System write blocked. ✅
Reason: [Errno 30] Read-only file system: '/app/system-write-test.txt'
```

This confirms that the tested system filesystem was read-only.

---

# 22. Private Application Data Write

The application writes:

```text
/data/app/sandbox-write-test.txt
```

The successful result was:

```text
Private app data write successful. ✅
Created: /data/app/sandbox-write-test.txt
```

---

# 23. `no_new_privs`

The sandbox enables:

```text
--no-new-privs
```

The test reported:

```text
NoNewPrivs: 1
```

This is a privilege-protection layer in the current sandbox design.

---

# 24. Capability Bounding Set

The sandbox uses:

```text
--bounding-set=-all
```

The runner reports:

```text
Capability bounding set: empty
```

This removes capabilities from the process capability bounding set.

---

# 25. Seccomp

Seccomp components are under:

```text
security/seccomp/
```

Important files:

```text
security/seccomp/lokeshos_seccomp.c
security/seccomp/seccomp_launcher.c
security/seccomp/seccomp_launcher_reference.c
security/seccomp/seccomp_launcher_test.c
security/seccomp/seccomp_profile_test.c
security/seccomp/seccomp_profile_test
```

The basic C launcher uses libseccomp.

The current test filter starts with:

```c
ctx = seccomp_init(SCMP_ACT_ALLOW);
```

and adds a test restriction for:

```text
getpid()
```

with:

```text
EPERM
```

The filter is loaded with:

```c
seccomp_load(ctx);
```

and then the requested program is executed with:

```c
execvp(argv[1], &argv[1]);
```

This is currently a security prototype/test policy, not yet a final production syscall policy.

---

# 26. Seccomp Launcher

Running:

```bash
security/seccomp/seccomp_profile_test
```

without arguments gives:

```text
Usage: security/seccomp/seccomp_profile_test <program> [args...]
```

When used by the sandbox, it reports:

```text
Seccomp allowlist loaded successfully.
```

---

# 27. Syscall Tracing

Syscall tracing was used to discover runtime requirements.

The trace contained system calls including:

```text
execve
brk
mmap
access
openat
fstat
close
read
pread64
arch_prctl
set_tid_address
set_robust_list
rseq
mprotect
```

The tracing runner is:

```text
security/sandbox/sandbox_trace_runner.py
```

The trace file is configured as:

```text
/trace/lokeshos-app.strace
```

This helped identify dependencies required by Python and the sandbox.

---

# 28. Sandbox Runner

Run:

```bash
python3 security/sandbox/sandbox_runner.py
```

Current configuration:

```text
Root filesystem:
/home/lokesh/LokeshOS/security/sandbox/rootfs

Application:
/app/test_app.py

Python:
/usr/bin/python3.13

Seccomp launcher:
/security/seccomp/seccomp_profile_test

App user:
lokeshos-app

UID:
997

GID:
985
```

The runner reports:

```text
Mount namespace: enabled
PID namespace: enabled
Non-root execution: enabled
Read-only system filesystem: enabled
Writable app data: enabled
no_new_privs: enabled
Capability bounding set: empty
Seccomp syscall filtering: enabled
```

---

# 29. Important Sandbox Errors and Fixes

## Missing `/proc`

Error:

```text
mount: .../rootfs/proc: mount point does not exist.
```

Fix:

```bash
sudo mkdir -p security/sandbox/rootfs/proc
sudo mkdir -p security/sandbox/rootfs/trace
```

## Missing `setpriv`

Error:

```text
chroot: failed to run command '/usr/bin/setpriv':
No such file or directory
```

Fix:

```bash
sudo mkdir -p security/sandbox/rootfs/usr/bin
sudo cp /usr/bin/setpriv security/sandbox/rootfs/usr/bin/
```

and its dependency:

```bash
sudo cp /lib/x86_64-linux-gnu/libcap-ng.so.0 security/sandbox/rootfs/lib/x86_64-linux-gnu/
```

## Missing dynamic loader

The rootfs lacked:

```text
/lib64/ld-linux-x86-64.so.2
```

Fix:

```bash
sudo mkdir -p security/sandbox/rootfs/lib64

sudo cp /lib64/ld-linux-x86-64.so.2 security/sandbox/rootfs/lib64/ld-linux-x86-64.so.2
```

## Missing Python

Error stage:

```text
execvp: No such file or directory
```

Fix:

```bash
sudo mkdir -p security/sandbox/rootfs/usr/bin
sudo cp /usr/bin/python3.13 security/sandbox/rootfs/usr/bin/
```

Then copy:

```bash
sudo mkdir -p security/sandbox/rootfs/usr/lib

sudo cp -a /usr/lib/python3.13 security/sandbox/rootfs/usr/lib/
```

## Missing Python shared libraries

Fix:

```bash
sudo mkdir -p security/sandbox/rootfs/lib/x86_64-linux-gnu

sudo cp -L /lib/x86_64-linux-gnu/libm.so.6 security/sandbox/rootfs/lib/x86_64-linux-gnu/

sudo cp -L /lib/x86_64-linux-gnu/libz.so.1 security/sandbox/rootfs/lib/x86_64-linux-gnu/

sudo cp -L /lib/x86_64-linux-gnu/libexpat.so.1 security/sandbox/rootfs/lib/x86_64-linux-gnu/
```

## Missing application

Error:

```text
/usr/bin/python3.13: can't open file '/app/test_app.py':
[Errno 2] No such file or directory
```

Fix:

```bash
sudo mkdir -p security/sandbox/rootfs/app

sudo cp security/sandbox/apps/test_app.py security/sandbox/rootfs/app/test_app.py
```

---

# 30. Final Successful Sandbox Test

Command:

```bash
cd ~/LokeshOS
python3 security/sandbox/sandbox_runner.py
```

Important result:

```text
Seccomp allowlist loaded successfully.
```

Application:

```text
=== LokeshOS Sandbox Security Test ===
Sandbox PID: 9
Sandbox UID: 997
Sandbox GID: 985
Filesystem root: /
```

Privilege:

```text
NoNewPrivs: 1
```

Filesystem isolation:

```text
Host home directory is NOT visible. ✅
```

Read-only system filesystem:

```text
System write blocked. ✅
```

Private writable data:

```text
Private app data write successful. ✅
```

Final:

```text
=== Security Test Complete ===

=== LokeshOS Sandbox + Seccomp finished ===
Launcher exit code: 0
```

This is the current successful sandbox milestone.

---

# 31. Git Initialization

Git was initialized for LokeshOS.

The first security/sandbox implementation was committed as:

```text
Initial LokeshOS security and sandbox implementation
```

Commit:

```text
5f1e78b
```

The commit contained:

```text
43 files changed
1073 insertions
```

---

# 32. `.gitignore` and Sensitive Files

A `.gitignore` file was created.

Sensitive files such as:

```text
security/auth/pin.hash
boot/initramfs/security/auth/pin.hash
```

were intentionally excluded from Git.

Verify:

```bash
git status
```

Do not commit:

- PINs.
- PIN hashes.
- Passwords.
- GitHub tokens.
- Private keys.
- Other credentials.

---

# 33. GitHub Repository

Repository:

```text
https://github.com/lokesh1725/LokeshOS
```

Local remote:

```bash
git remote add origin https://github.com/lokesh1725/LokeshOS.git
```

Verify:

```bash
git remote -v
```

Expected:

```text
origin  https://github.com/lokesh1725/LokeshOS.git (fetch)
origin  https://github.com/lokesh1725/LokeshOS.git (push)
```

---

# 34. GitHub CLI Authentication

GitHub CLI version was:

```text
gh version 2.86.0
```

Authentication:

```bash
gh auth login
```

Selections:

```text
GitHub.com
HTTPS
Authenticate Git with GitHub credentials: Yes
Login with a web browser
```

Browser/device authentication completed successfully.

Verify:

```bash
gh auth status
```

The active account was:

```text
lokesh1725
```

Never put the actual token in documentation.

---

# 35. First GitHub Push

Push:

```bash
git push -u origin main
```

Successful result:

```text
[new branch] main -> main
branch 'main' set up to track 'origin/main'
```

The repository is now connected to:

```text
origin/main
```

---

# 36. Verify Local Git

Run:

```bash
git status
```

Expected when clean:

```text
On branch main
Your branch is up to date with 'origin/main'.

nothing to commit, working tree clean
```

---

# 37. Verify Tracked Files

Local:

```bash
git ls-files
```

Remote:

```bash
git ls-tree -r --name-only origin/main
```

These were checked and matched for the committed project contents.

---

# 38. Current Git Rules

Before development:

```bash
cd ~/LokeshOS
git status
```

After editing:

```bash
git status
git diff
```

Before staging:

```bash
git diff --stat
```

After staging:

```bash
git diff --cached --stat
```

Then:

```bash
git commit -m "Describe the change"
```

Then:

```bash
git push
```

Finally:

```bash
git status
```

---

# 39. Current Security Architecture

Conceptually:

```text
                         LokeshOS
                            |
             +--------------+--------------+
             |                             |
       Encrypted Storage              Boot / Initramfs
             |                             |
            LUKS2                     Authentication
                                           |
                                      PIN / bcrypt
                                           |
                                      Security tools
                                           |
                                        Sandbox
                                           |
                 +-------------------------+-----------------------+
                 |             |             |          |           |
             Mount NS       PID NS       Non-root   no_new_privs  Seccomp
                 |             |             |          |           |
                 +-------------+-------------+----------+-----------+
                                           |
                              Read-only system filesystem
                                           |
                              Writable private app data
                                           |
                                   Test application
```

---

# 40. Security Layers Currently Demonstrated

| Layer | State |
|---|---|
| LUKS2 encrypted storage | Implemented |
| PIN authentication | Implemented |
| bcrypt authentication | Implemented |
| Initramfs authentication components | Implemented |
| Custom initramfs tree | Implemented |
| Linux kernel image | Present |
| Sandbox root filesystem | Implemented |
| Mount namespace | Implemented |
| PID namespace | Implemented |
| Dedicated non-root UID/GID | Implemented |
| `no_new_privs` | Implemented |
| Empty capability bounding set | Implemented |
| Read-only system filesystem | Tested successfully |
| Writable private app data | Tested successfully |
| Host home isolation | Tested successfully |
| Seccomp | Implemented/tested |
| Syscall tracing | Implemented |
| Python runtime inside sandbox | Added |
| Git repository | Implemented |
| GitHub remote | Implemented |
| Initial GitHub push | Completed |

---

# 41. Current Milestone

The current major successful milestone is:

> **LokeshOS has a working security sandbox prototype that successfully runs a test application with namespace isolation, non-root execution, `no_new_privs`, an empty capability bounding set, a read-only system filesystem, writable private application data, host-home isolation, and seccomp loading.**

The final test returned:

```text
Launcher exit code: 0
```

---

# 42. Current Development Position

The project has progressed from the initial security foundation to a working security prototype.

Current flow:

```text
LUKS2
  ↓
PIN / bcrypt authentication
  ↓
Initramfs security components
  ↓
Sandbox root filesystem
  ↓
Mount namespace
  ↓
PID namespace
  ↓
Non-root application
  ↓
no_new_privs
  ↓
Empty capability bounding set
  ↓
Read-only system filesystem
  ↓
Private writable application data
  ↓
Seccomp
  ↓
Security test application
```

---

# 43. Next Development Direction

The next major development should continue from the current working state rather than repeatedly recreating already completed dependencies.

The next areas are:

1. Continue boot/initramfs integration.
2. Integrate authentication into the boot flow.
3. Improve the initramfs userspace.
4. Integrate the sandbox as an OS security component.
5. Develop a defined seccomp policy for the intended application environment.
6. Make the build process reproducible.
7. Build a complete boot image.
8. Test booting the system in a controlled environment.
9. Continue security testing.
10. Document every verified milestone.
11. Commit verified source changes.
12. Push verified commits to GitHub.

---

# 44. Useful Commands

Enter project:

```bash
cd ~/LokeshOS
```

Git status:

```bash
git status
```

Git changes:

```bash
git diff
```

Tracked files:

```bash
git ls-files
```

Remote:

```bash
git remote -v
```

Authentication:

```bash
python3 security/auth/auth.py
```

Sandbox:

```bash
python3 security/sandbox/sandbox_runner.py
```

Syscall tracing:

```bash
python3 security/sandbox/sandbox_trace_runner.py
```

Seccomp launcher:

```bash
security/seccomp/seccomp_profile_test
```

Python dependencies:

```bash
ldd /usr/bin/python3.13
```

Sandbox rootfs:

```bash
find security/sandbox/rootfs -maxdepth 3 -type f | sort
```

Initramfs:

```bash
find boot/initramfs -maxdepth 3 -type f | sort
```

Push:

```bash
git push
```

---

# 45. Documentation Workflow

This file is intended to be the running LokeshOS engineering record.

For every future milestone record:

1. Goal.
2. Files created/modified.
3. Packages installed.
4. Commands executed.
5. Error encountered.
6. Fix applied.
7. Test command.
8. Test result.
9. Git changes.
10. Commit.
11. Push.
12. Next goal.

Do not record secrets.

---

# 46. Final Current-State Summary

LokeshOS currently has:

- A project directory at `~/LokeshOS`.
- A Git repository.
- GitHub remote `origin`.
- GitHub CLI authentication.
- A successful initial GitHub push.
- LUKS2 secure-storage foundation.
- bcrypt PIN authentication.
- Initramfs authentication/security components.
- A custom initramfs tree.
- A Linux kernel image at `kernel/linux/arch/x86/boot/bzImage`.
- A sandbox root filesystem.
- A dedicated non-root application identity.
- Mount namespace isolation.
- PID namespace isolation.
- `no_new_privs`.
- Empty capability bounding set.
- Read-only system filesystem.
- Writable private application data.
- Host-home isolation.
- Seccomp filtering.
- Syscall tracing.
- Python 3.13 inside the sandbox.
- A successful end-to-end sandbox security test.

Latest successful sandbox result:

```text
=== Security Test Complete ===

=== LokeshOS Sandbox + Seccomp finished ===
Launcher exit code: 0
```

---

# 47. GitHub

Repository:

```text
https://github.com/lokesh1725/LokeshOS
```

Local:

```text
~/LokeshOS
```

Branch:

```text
main
```

Initial security/sandbox commit:

```text
5f1e78b
```

Commit message:

```text
Initial LokeshOS security and sandbox implementation
```

---

# End of Current LokeshOS Documentation

Continue this file as the project develops. Preserve previous milestones and add new verified work chronologically.
