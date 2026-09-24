#!/usr/bin/env python3

import os
from pathlib import Path

print("=== LokeshOS Sandbox Security Test ===")

print(f"Sandbox PID: {os.getpid()}")
print(f"Sandbox UID: {os.getuid()}")
print(f"Sandbox GID: {os.getgid()}")
print(f"Filesystem root: {Path('/').resolve()}")
print("\n=== Privilege Protection ===")

status_file = Path("/proc/self/status")

try:
    for line in status_file.read_text().splitlines():
        if line.startswith("NoNewPrivs:"):
            print(line)

except Exception as e:
    print(f"Could not read process status: {e}")
print("\n=== Filesystem Visibility ===")

try:
    print("Root filesystem:")
    for item in Path("/").iterdir():
        print(f"  {item}")
except PermissionError:
    print("Permission denied")

print("\n=== Private App Data ===")

private_data = Path("/data/app-data.txt")

if private_data.exists():
    print("Private data found:")
    print(private_data.read_text().strip())
else:
    print("Private data NOT found.")

print("\n=== Host Home Test ===")

host_home = Path("/home/lokesh")

if host_home.exists():
    print("WARNING: Host home directory is visible!")
else:
    print("Host home directory is NOT visible. ✅")

print("\n=== System Filesystem Write Test ===")

system_test = Path("/app/system-write-test.txt")

try:
    system_test.write_text("This should NOT be allowed.")
    print("WARNING: System filesystem is writable! ❌")
except Exception as e:
    print(f"System write blocked. ✅")
    print(f"Reason: {e}")

print("\n=== Private App Data Write Test ===")

app_data_dir = Path("/data/app")

app_data_dir.mkdir(parents=True, exist_ok=True)

app_test = app_data_dir / "sandbox-write-test.txt"

try:
    app_test.write_text("LokeshOS sandbox private data")
    print("Private app data write successful. ✅")
    print(f"Created: {app_test}")
except Exception as e:
    print("Private app data write FAILED. ❌")
    print(f"Reason: {e}")

print("\n=== Security Test Complete ===")

