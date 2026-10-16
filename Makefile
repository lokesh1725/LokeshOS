# ============================================================
# LokeshOS — reproducible build
# ============================================================
#
# Common targets:
#   make              Build C helpers + pack boot/initramfs.img
#   make kernel       Copy the built kernel image to boot/vmlinuz
#   make image        Build kernel copy + initramfs (bootable pair)
#   make run          Boot the image in QEMU (serial console)
#   make test         Run host-side security tests
#   make clean        Remove staging area + initramfs image
#   make distclean    clean + remove boot/vmlinuz
#
# The build is staged under build/ and never mutates the source tree.
# ============================================================

SHELL := /bin/sh

# ---- layout -------------------------------------------------
ROOT           := $(CURDIR)
BUILD          := $(ROOT)/build
STAGE          := $(BUILD)/initramfs

BOOT           := $(ROOT)/boot
BASE_INITRAMFS := $(BOOT)/initramfs
INITRAMFS_IMG  := $(BOOT)/initramfs.img
VMLINUZ        := $(BOOT)/vmlinuz
ISO            := $(BOOT)/lokeshos.iso

SANDBOX_ROOTFS := $(ROOT)/security/sandbox/rootfs
KERNEL_SRC     ?= $(ROOT)/kernel/linux
KERNEL_IMG      = $(KERNEL_SRC)/arch/x86/boot/bzImage

# ---- tools --------------------------------------------------
CC             ?= gcc
CPIO           ?= cpio
GZIP           ?= gzip
TAR            ?= tar
QEMU           ?= qemu-system-x86_64

CFLAGS_PROD    ?= -O2 -Wall -Wextra
CFLAGS_STATIC  ?= -O2 -Wall -Wextra -static

# ---- build products (paths inside the staged initramfs) -----
AUTH_BIN    := $(STAGE)/security/auth/pin_auth
RUNAS_BIN   := $(STAGE)/bin/runas
GETPID_BIN  := $(STAGE)/security/seccomp/seccomp_launcher
GETPID_TEST  = $(STAGE)/security/seccomp/getpid_test
POLICY_BIN  := $(STAGE)/security/seccomp/seccomp_policy

C_SOURCES := \
	security/auth/pin_auth.c \
	security/auth/runas.c \
	security/seccomp/seccomp_launcher.c \
	security/seccomp/seccomp_policy.c \
	security/seccomp/getpid_test.c

.PHONY: all prepare binaries initramfs kernel image iso run run-iso test clean distclean check \
	$(AUTH_BIN) $(RUNAS_BIN) $(GETPID_BIN) $(GETPID_TEST) $(POLICY_BIN)

all: initramfs

# ============================================================
# Staging
# ============================================================

prepare:
	@rm -rf $(STAGE)
	@mkdir -p $(STAGE)
	@echo "  STAGE  copying base initramfs tree"
	@$(TAR) -C $(BASE_INITRAMFS) -cf - \
		--exclude='./security/sandbox/rootfs' \
		--exclude='./bin/runas' \
		--exclude='./security/auth/pin_auth' \
		--exclude='./security/auth/pin.hash' \
		--exclude='./security/seccomp/seccomp_launcher' \
		--exclude='./security/seccomp/seccomp_profile_test' \
		--exclude='./security/seccomp/getpid_test' \
		. | $(TAR) -C $(STAGE) -xf -
	@rm -rf $(STAGE)/security/sandbox/rootfs
	@mkdir -p $(STAGE)/security/sandbox/rootfs
	@mkdir -p $(STAGE)/security/seccomp
	@mkdir -p $(STAGE)/security/auth
	@mkdir -p $(STAGE)/bin
	@echo "  LINK   busybox applet symlinks"
	@for a in chroot unshare poweroff reboot; do \
		ln -sf busybox $(STAGE)/bin/$$a; \
	done

# ============================================================
# C helpers
# ============================================================

binaries: prepare $(AUTH_BIN) $(RUNAS_BIN) $(GETPID_BIN) $(GETPID_TEST) $(POLICY_BIN)

$(AUTH_BIN): security/auth/pin_auth.c
	@echo "  CC     pin_auth"
	@$(CC) $(CFLAGS_STATIC) -o $@ $<

$(RUNAS_BIN): security/auth/runas.c
	@echo "  CC     runas"
	@$(CC) $(CFLAGS_STATIC) -o $@ $<

$(GETPID_BIN): security/seccomp/seccomp_launcher.c
	@echo "  CC     seccomp_launcher"
	@$(CC) $(CFLAGS_STATIC) -o $@ $< -lseccomp

$(POLICY_BIN): security/seccomp/seccomp_policy.c
	@echo "  CC     seccomp_policy"
	@$(CC) $(CFLAGS_STATIC) -o $@ $< -lseccomp

$(GETPID_TEST): security/seccomp/getpid_test.c
	@echo "  CC     getpid_test"
	@$(CC) $(CFLAGS_STATIC) -o $@ $<

# ============================================================
# Sandbox rootfs + initramfs image
# ============================================================

initramfs: binaries
	@echo "  ROOTFS staging sandbox rootfs"
	@$(TAR) -C $(SANDBOX_ROOTFS) -cf - \
		--exclude='./security/seccomp/seccomp_profile_test' . \
		| $(TAR) -C $(STAGE)/security/sandbox/rootfs -xf -
	@mkdir -p $(STAGE)/security/sandbox/rootfs/security/seccomp
	@cp $(POLICY_BIN) $(STAGE)/security/sandbox/rootfs/security/seccomp/seccomp_policy
	@echo "  LAUNCH installing sandbox launcher"
	@mkdir -p $(STAGE)/security/sandbox
	@cp $(ROOT)/security/sandbox/sandbox_launch.sh $(STAGE)/security/sandbox/sandbox_launch.sh
	@chmod 755 $(STAGE)/security/sandbox/sandbox_launch.sh
	@echo "  CPIO   packing $(INITRAMFS_IMG)"
	@cd $(STAGE) && find . -print0 | LC_ALL=C sort -z \
		| $(CPIO) --null --reproducible -o -H newc 2>/dev/null \
		| $(GZIP) -9n > $(INITRAMFS_IMG)
	@echo "  OK     $(INITRAMFS_IMG) ($$(du -h $(INITRAMFS_IMG) | cut -f1))"

# ============================================================
# Kernel
# ============================================================

kernel:
	@if [ -f $(VMLINUZ) ] && [ -z "$(KERNEL_FORCE)" ]; then \
		echo "  SKIP   $(VMLINUZ) already present (set KERNEL_FORCE=1 to replace)"; \
	else \
		test -f $(KERNEL_IMG) || { \
			echo "kernel image not found: $(KERNEL_IMG)"; \
			echo "build it with: make -C $(KERNEL_SRC) -j\$$(nproc)"; \
			exit 1; }; \
		cp $(KERNEL_IMG) $(VMLINUZ); \
		echo "  OK     $(VMLINUZ)"; \
	fi

image: kernel initramfs

# ============================================================
# Bootable ISO
# ============================================================

iso: image
	@sh $(ROOT)/scripts/mkiso.sh $(ISO)

# ============================================================
# Run (serial console)
# ============================================================

QEMU_MEM   ?= 512
QEMU_EXTRA ?=
run: image
	$(QEMU) -m $(QEMU_MEM) \
		-kernel $(VMLINUZ) \
		-initrd $(INITRAMFS_IMG) \
		-nographic -no-reboot \
		-append "console=ttyS0 panic=1" $(QEMU_EXTRA)

run-iso: iso
	$(QEMU) -m $(QEMU_MEM) -cdrom $(ISO) \
		-nographic -no-reboot -boot d $(QEMU_EXTRA)

# ============================================================
# Tests / cleanup
# ============================================================

test:
	@sh $(ROOT)/tests/run_tests.sh

check: $(C_SOURCES)
	@for f in $(C_SOURCES); do \
		echo "  CHECK  $$f"; \
		$(CC) -fsyntax-only -Wall -Wextra $$f || exit 1; \
	done

clean:
	@rm -rf $(BUILD)
	@rm -f $(INITRAMFS_IMG)
	@echo "  OK     cleaned build/ and initramfs.img"

distclean: clean
	@rm -f $(VMLINUZ) $(ISO)
	@echo "  OK     removed boot/vmlinuz and boot/lokeshos.iso"
