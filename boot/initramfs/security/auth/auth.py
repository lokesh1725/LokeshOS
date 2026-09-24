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
