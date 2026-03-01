SHELL := /bin/bash
PWD_DIR=$(abspath .)
KERNEL_VERSION:=6.18.15

# Build target bitness: 32 or 64 (default: 32)
BITS ?= 32

# Host architecture detection
HOST_ARCH := $(shell uname -m)

# Cross-compiler and target ISA selection based on BITS and HOST_ARCH:
#   32-bit: always cross-compile with riscv64-linux-gnu- (works on any host)
#   64-bit: cross-compile with riscv64-linux-gnu- unless running natively on riscv64
ifeq ($(BITS),64)
  ifeq ($(HOST_ARCH),riscv64)
    CROSS_COMPILE ?=
  else
    CROSS_COMPILE ?= riscv64-linux-gnu-
  endif
  RISCV_XLEN  := 64
  RISCV_ISA   := rv64imac_zicntr_zicsr_zifencei
  RISCV_MARCH := rv64imac_zicsr_zifencei
  RISCV_ABI   := lp64
else
  BITS         := 32
  CROSS_COMPILE ?= riscv64-linux-gnu-
  RISCV_XLEN  := 32
  RISCV_ISA   := rv32imac_zicntr_zicsr_zifencei
  RISCV_MARCH := rv32ima_zicsr_zifencei_zicntr
  RISCV_ABI   := ilp32
endif

# Per-bitness output directories so 32 and 64 builds coexist
OBJDIR         := $(PWD_DIR)/build$(BITS)
OPENSBI_OBJDIR := $(PWD_DIR)/opensbi-build$(BITS)

# Per-bitness initramfs outputs
INITRAMFS_DIR  := $(PWD_DIR)/initramfs$(BITS)
INITRAMFS_CPIO := $(PWD_DIR)/initramfs$(BITS).cpio.gz

# Buildroot per-bitness clone directory
BUILDROOT_DIR  := $(PWD_DIR)/buildroot$(BITS)

# Spike (riscv-isa-sim) source and build directories
SPIKE_DIR   := $(PWD_DIR)/spike
SPIKE_BUILD := $(PWD_DIR)/spike-build
# Use the locally-built spike when available, fall back to PATH
SPIKE       := $(if $(wildcard $(SPIKE_BUILD)/bin/spike),$(SPIKE_BUILD)/bin/spike,spike)

NPROC     := $(shell nproc)
QEMU_MEM     ?= 512
# Optional: set QEMU_TIMEOUT=N (seconds) to auto-exit after N seconds.
# Default is empty (run until Ctrl-C or guest halts).
QEMU_TIMEOUT ?=
SPIKE_MEM    ?= 512

# Prefix command with timeout if QEMU_TIMEOUT is set
IF_TIMEOUT = $(if $(QEMU_TIMEOUT),timeout $(QEMU_TIMEOUT),)

# Release package name and output tarball path
RELEASE_NAME    := linux-riscv-rv$(BITS)-v$(KERNEL_VERSION)
RELEASE_TARBALL := $(PWD_DIR)/dist/$(RELEASE_NAME).tar.gz
# Staging directory under dist/ (cleaned after tarball is created)
RELEASE_STAGING := $(PWD_DIR)/dist/$(RELEASE_NAME)

# All kernel make invocations use a separate output dir via O=
KERNEL_MAKE := make -C linux O=$(OBJDIR) ARCH=riscv CROSS_COMPILE=$(CROSS_COMPILE) -j$(NPROC)
# scripts/config wrapper that operates on the per-bitness .config
KCONFIG := linux/scripts/config --file $(OBJDIR)/.config

all:
	@echo "PWD:           $(PWD_DIR)"
	@echo "Kernel:        $(KERNEL_VERSION)"
	@echo "Host arch:     $(HOST_ARCH)"
	@echo "Target bits:   $(BITS)  (override with BITS=32 or BITS=64)"
	@echo "Cross-compile: $(if $(CROSS_COMPILE),$(CROSS_COMPILE),(native))"
	@echo "Kernel objdir: $(OBJDIR)"
	@echo "Initramfs:     $(INITRAMFS_CPIO)"
	@echo ""
	@echo "--- Source ---"
	@echo "  linux                        - Download and extract Linux kernel source"
	@echo "  opensbi                      - Clone OpenSBI source"
	@echo "  buildroot                    - Clone Buildroot source ($(BITS)-bit)"
	@echo "  spike_src                    - Clone Spike (riscv-isa-sim) source"
	@echo ""
	@echo "--- Kernel ---"
	@echo "  build_linux                  - Build Linux kernel (rv$(BITS)imac no-FPU)"
	@echo ""
	@echo "--- Initramfs ---"
	@echo "  make_initramfs_simple        - Build init_loop initramfs ($(BITS)-bit)"
	@echo "  make_initramfs_buildroot     - Build Buildroot initramfs ($(BITS)-bit)"
	@echo "  install_initramfs            - Embed INITRAMFS_CPIO into kernel and rebuild"
	@echo "  build_init                   - Build the init_loop ELF ($(BITS)-bit)"
	@echo ""
	@echo "--- Firmware ---"
	@echo "  build_opensbi                - Build OpenSBI only ($(BITS)-bit)"
	@echo "  build_opensbi_with_kernel    - Build OpenSBI + kernel FW_PAYLOAD ($(BITS)-bit)"
	@echo "  build_spike                  - Build Spike simulator from source"
	@echo ""
	@echo "--- Test ---"
	@echo "  test_qemu                    - Boot fw_payload.bin in QEMU ($(BITS)-bit)"
	@echo "  test_qemu_kernel             - Boot kernel+initramfs separately in QEMU ($(BITS)-bit)"
	@echo "  test_spike                   - Boot fw_payload.elf in Spike ($(BITS)-bit) [auto-uses local build]"
	@echo "  Spike binary: $(SPIKE)"
	@echo ""
	@echo "--- Batch ---"
	@echo "  build_all                    - Build Linux + OpenSBI for both 32 and 64 bit"
	@echo "  clean                        - Remove all build artefacts"
	@echo ""
	@echo "--- Package & Release ---"
	@echo "  package                      - Bundle rv$(BITS) artifacts → $(RELEASE_TARBALL)"
	@echo "  package_all                  - Bundle rv32 + rv64 tarballs"
	@echo "  github_release               - Create GitHub Release and upload tarballs (requires gh CLI)"
	@echo "  clean_packages               - Remove release tarballs from workspace"
	@echo ""
	@echo "Examples:"
	@echo "  make BITS=32 build_linux make_initramfs_simple install_initramfs build_opensbi_with_kernel"
	@echo "  make BITS=64 build_linux make_initramfs_buildroot install_initramfs build_opensbi_with_kernel"
	@echo "  make BITS=32 test_qemu"
	@echo "  make package_all"
	@echo "  make github_release TAG=v$(KERNEL_VERSION)"

# ---------------------------------------------------------------------------
# Source acquisition
# ---------------------------------------------------------------------------

linux:
	@if [ -d linux ]; then echo "linux/ already exists, skipping download"; else \
		wget https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-$(KERNEL_VERSION).tar.xz && \
		tar -xf linux-$(KERNEL_VERSION).tar.xz && \
		mv linux-$(KERNEL_VERSION) linux && \
		rm linux-$(KERNEL_VERSION).tar.xz; \
	fi

opensbi:
	@if [ -d opensbi ]; then echo "opensbi/ already exists, skipping clone"; else \
		git clone https://github.com/riscv-software-src/opensbi; \
	fi

spike_src:
	@if [ -d spike ]; then echo "spike/ already exists, skipping clone"; else \
		git clone https://github.com/riscv-software-src/riscv-isa-sim spike; \
	fi

build_spike: spike_src
	mkdir -p $(SPIKE_BUILD)
	cd $(SPIKE_BUILD) && $(SPIKE_DIR)/configure --prefix=$(SPIKE_BUILD)
	$(MAKE) -C $(SPIKE_BUILD) -j$(NPROC)
	$(MAKE) -C $(SPIKE_BUILD) install
	@echo "Spike built: $(SPIKE_BUILD)/bin/spike"

buildroot:
	@if [ -d $(BUILDROOT_DIR) ]; then \
		echo "$(BUILDROOT_DIR) already exists, skipping clone"; \
	else \
		git clone --depth=1 https://github.com/buildroot/buildroot $(BUILDROOT_DIR); \
	fi

# ---------------------------------------------------------------------------
# Kernel build
# ---------------------------------------------------------------------------

build_linux: linux
	mkdir -p $(OBJDIR)
	$(KERNEL_MAKE) defconfig
	# Use rv$(BITS)imac (no FPU/D) for both 32 and 64 bit to minimise CPU requirements
ifeq ($(BITS),32)
	$(KCONFIG) --enable  CONFIG_NONPORTABLE
	$(KCONFIG) --disable CONFIG_ARCH_RV64I
	$(KCONFIG) --enable  CONFIG_ARCH_RV32I
endif
	$(KCONFIG) --disable CONFIG_FPU
	$(KCONFIG) --disable CONFIG_RISCV_ISA_ZAWRS
	$(KCONFIG) --disable CONFIG_RISCV_ISA_ZBA
	$(KCONFIG) --disable CONFIG_RISCV_ISA_ZBB
	$(KCONFIG) --disable CONFIG_RISCV_ISA_ZBC
	$(KCONFIG) --disable CONFIG_RISCV_ISA_ZICBOM
	$(KCONFIG) --disable CONFIG_RISCV_ISA_ZICBOZ
	$(KERNEL_MAKE) olddefconfig
	$(KERNEL_MAKE)

# ---------------------------------------------------------------------------
# Simple initramfs (init_loop only)
# ---------------------------------------------------------------------------

# Build just the init_loop ELF binary into payload/
build_init:
	make -C payload BITS=$(BITS) CROSS_COMPILE=$(CROSS_COMPILE) init_loop

# ---------------------
# Simple initramfs (init_loop)
# Calls build_init then assembles a minimal root FS and packs it.
# ---------------------
make_initramfs_simple:
	$(MAKE) build_init
	mkdir -p $(INITRAMFS_DIR)/{bin,dev,etc,lib,lib64,mnt/root,proc,root,sbin,sys,run}
	cp payload/init $(INITRAMFS_DIR)/init
	# Create device nodes (idempotent, requires sudo)
	sudo mknod -m 600 $(INITRAMFS_DIR)/dev/console c 5 1 2>/dev/null || true
	sudo mknod -m 666 $(INITRAMFS_DIR)/dev/null   c 1 3 2>/dev/null || true
	sudo mknod -m 660 $(INITRAMFS_DIR)/dev/sda    b 8 0 2>/dev/null || true
	# Pack into cpio.gz
	(cd $(INITRAMFS_DIR) && find . | cpio -o --format=newc | gzip > $(INITRAMFS_CPIO))
	@echo "Simple initramfs: $(INITRAMFS_CPIO)"

# ---------------------------------------------------------------------------
# Buildroot initramfs
# ---------------------------------------------------------------------------

make_initramfs_buildroot: buildroot
	# Use the QEMU virt defconfig for rv$(BITS) as base (tested, already enables cpio+gzip)
	make -C $(BUILDROOT_DIR) qemu_riscv$(BITS)_virt_defconfig
	# Append config fragment to guarantee cpio.gz output
	printf 'BR2_TARGET_ROOTFS_CPIO=y\nBR2_TARGET_ROOTFS_CPIO_GZIP=y\n' \
		>> $(BUILDROOT_DIR)/.config
	make -C $(BUILDROOT_DIR) BR2_DEFCONFIG=$(BUILDROOT_DIR)/.config olddefconfig
	make -C $(BUILDROOT_DIR) -j$(NPROC)
	cp $(BUILDROOT_DIR)/output/images/rootfs.cpio.gz $(INITRAMFS_CPIO)
	@echo "Buildroot initramfs: $(INITRAMFS_CPIO)"

# ---------------------------------------------------------------------------
# Embed initramfs into kernel Image (CONFIG_INITRAMFS_SOURCE)
# ---------------------------------------------------------------------------

install_initramfs:
	@test -f $(INITRAMFS_CPIO) || \
		(echo "ERROR: $(INITRAMFS_CPIO) not found. Run make_initramfs_simple or make_initramfs_buildroot first." && false)
	$(KCONFIG) --set-str CONFIG_INITRAMFS_SOURCE $(INITRAMFS_CPIO)
	$(KERNEL_MAKE) olddefconfig
	$(KERNEL_MAKE)
	@echo "Kernel with embedded initramfs: $(OBJDIR)/arch/riscv/boot/Image"

# ---------------------------------------------------------------------------
# OpenSBI firmware
# ---------------------------------------------------------------------------

build_opensbi: opensbi
	make -C opensbi \
		O=$(OPENSBI_OBJDIR) \
		PLATFORM_RISCV_ISA=$(RISCV_ISA) \
		CROSS_COMPILE=$(CROSS_COMPILE) \
		PLATFORM_RISCV_XLEN=$(RISCV_XLEN) \
		PLATFORM=generic \
		-j$(NPROC)

build_opensbi_with_kernel: opensbi
	make -C opensbi \
		O=$(OPENSBI_OBJDIR) \
		PLATFORM_RISCV_ISA=$(RISCV_ISA) \
		CROSS_COMPILE=$(CROSS_COMPILE) \
		PLATFORM_RISCV_XLEN=$(RISCV_XLEN) \
		PLATFORM=generic \
		FW_PAYLOAD_PATH=$(OBJDIR)/arch/riscv/boot/Image \
		-j$(NPROC)

# ---------------------------------------------------------------------------
# QEMU tests
# ---------------------------------------------------------------------------
#
# test_qemu:        boot the self-contained fw_payload (OpenSBI + kernel embedded)
# test_qemu_kernel: boot OpenSBI fw_dynamic + separate kernel Image + initramfs
#                   (useful to iterate without rebuilding firmware)

QEMU_BASE := qemu-system-riscv$(BITS) -M virt -m $(QEMU_MEM)M -nographic

test_qemu:
	@test -f $(OPENSBI_OBJDIR)/platform/generic/firmware/fw_payload.bin || \
		(echo "ERROR: fw_payload.bin not found. Run build_opensbi_with_kernel first." && false)
	$(IF_TIMEOUT) $(QEMU_BASE) \
		-bios $(OPENSBI_OBJDIR)/platform/generic/firmware/fw_payload.bin

test_qemu_kernel:
	@test -f $(OBJDIR)/arch/riscv/boot/Image || \
		(echo "ERROR: kernel Image not found. Run build_linux first." && false)
	@test -f $(INITRAMFS_CPIO) || \
		(echo "ERROR: $(INITRAMFS_CPIO) not found. Run make_initramfs_simple or make_initramfs_buildroot first." && false)
	$(IF_TIMEOUT) $(QEMU_BASE) \
		-bios $(OPENSBI_OBJDIR)/platform/generic/firmware/fw_dynamic.bin \
		-kernel $(OBJDIR)/arch/riscv/boot/Image \
		-initrd $(INITRAMFS_CPIO) \
		-append "root=/dev/ram rdinit=/init console=ttyS0 earlycon=sbi"

# ---------------------------------------------------------------------------
# Spike tests
#
# Uses the locally-built Spike when spike-build/bin/spike exists (via build_spike),
# otherwise falls back to the system 'spike' in PATH.
# The generic OpenSBI fw_payload.elf works with Spike's built-in HTIF/SBI.
# ---------------------------------------------------------------------------

test_spike:
	@test -x $(SPIKE) 2>/dev/null || command -v $(SPIKE) >/dev/null 2>&1 || \
		(echo "ERROR: spike not found. Run 'make build_spike' or install from https://github.com/riscv-software-src/riscv-isa-sim" && false)
	@test -f $(OPENSBI_OBJDIR)/platform/generic/firmware/fw_payload.elf || \
		(echo "ERROR: fw_payload.elf not found. Run build_opensbi_with_kernel first." && false)
	$(SPIKE) --isa=$(RISCV_ISA) -m$(SPIKE_MEM) \
		$(OPENSBI_OBJDIR)/platform/generic/firmware/fw_payload.elf

# ---------------------------------------------------------------------------
# Batch and housekeeping
# ---------------------------------------------------------------------------

build_all: linux opensbi
	$(MAKE) BITS=32 build_linux make_initramfs_simple install_initramfs build_opensbi_with_kernel
	$(MAKE) BITS=64 build_linux make_initramfs_simple install_initramfs build_opensbi_with_kernel

# ---------------------------------------------------------------------------
# Package: bundle build artifacts into a distributable tarball
#
# Usage:
#   make BITS=32 package   → linux-riscv-rv32-v<ver>.tar.gz
#   make BITS=64 package   → linux-riscv-rv64-v<ver>.tar.gz
#   make package_all       → both tarballs
# ---------------------------------------------------------------------------

package:
	@echo "--- Checking artifacts for rv$(BITS) ---"
	@test -f $(OPENSBI_OBJDIR)/platform/generic/firmware/fw_payload.bin || \
		(echo "ERROR: fw_payload.bin not found. Run build_opensbi_with_kernel first." && false)
	@test -f $(OPENSBI_OBJDIR)/platform/generic/firmware/fw_payload.elf || \
		(echo "ERROR: fw_payload.elf not found. Run build_opensbi_with_kernel first." && false)
	@test -f $(OPENSBI_OBJDIR)/platform/generic/firmware/fw_dynamic.bin || \
		(echo "ERROR: fw_dynamic.bin not found. Run build_opensbi first." && false)
	@test -f $(OBJDIR)/arch/riscv/boot/Image || \
		(echo "ERROR: Image not found. Run build_linux first." && false)
	@test -f $(INITRAMFS_CPIO) || \
		(echo "ERROR: $(INITRAMFS_CPIO) not found. Run make_initramfs_simple or make_initramfs_buildroot first." && false)
	@echo "--- Assembling $(RELEASE_NAME) ---"
	rm -rf $(RELEASE_STAGING)
	mkdir -p $(PWD_DIR)/dist
	mkdir -p $(RELEASE_STAGING)
	cp $(OPENSBI_OBJDIR)/platform/generic/firmware/fw_payload.bin $(RELEASE_STAGING)/
	cp $(OPENSBI_OBJDIR)/platform/generic/firmware/fw_payload.elf $(RELEASE_STAGING)/
	cp $(OPENSBI_OBJDIR)/platform/generic/firmware/fw_dynamic.bin $(RELEASE_STAGING)/
	cp $(OBJDIR)/arch/riscv/boot/Image                            $(RELEASE_STAGING)/
	cp $(INITRAMFS_CPIO)                                          $(RELEASE_STAGING)/initramfs.cpio.gz
	cp $(OBJDIR)/vmlinux                                          $(RELEASE_STAGING)/
	@echo "--- Generating README.md ---"
	@( \
	  echo "# Linux $(KERNEL_VERSION) for RISC-V rv$(BITS)imac (no FPU)"; \
	  echo ""; \
	  echo "| Field | Value |"; \
	  echo "|-------|-------|"; \
	  echo "| ISA   | \`$(RISCV_ISA)\` |"; \
	  echo "| ABI   | \`$(RISCV_ABI)\` |"; \
	  echo "| Build | $$(date +%Y-%m-%d) |"; \
	  echo ""; \
	  echo "## Files"; \
	  echo ""; \
	  echo "| File | Description |"; \
	  echo "|------|-------------|"; \
	  echo "| \`fw_payload.bin\` | OpenSBI firmware with Linux kernel embedded — QEMU one-shot boot |"; \
	  echo "| \`fw_payload.elf\` | OpenSBI + kernel ELF for Spike simulator |"; \
	  echo "| \`fw_dynamic.bin\` | OpenSBI dynamic firmware (use alongside a separate kernel \`Image\`) |"; \
	  echo "| \`Image\` | Linux kernel image (rv$(BITS)imac, no FPU) |"; \
	  echo "| \`initramfs.cpio.gz\` | Minimal root filesystem (cpio + gzip) |"; \
	  echo "| \`vmlinux\` | Unstripped kernel ELF with debug symbols — for use with GDB / JTAG |"; \
	  echo ""; \
	  echo "## Quickstart"; \
	  echo ""; \
	  echo "### 1. QEMU — single-file boot with \`fw_payload.bin\` (simplest)"; \
	  echo ""; \
	  echo '```bash'; \
	  echo "qemu-system-riscv$(BITS) -M virt -m 512M -nographic \\"; \
	  echo "    -bios fw_payload.bin"; \
	  echo '```'; \
	  echo ""; \
	  echo "### 2. QEMU — separate kernel + initramfs (\`fw_dynamic\` + \`Image\`)"; \
	  echo ""; \
	  echo '```bash'; \
	  echo "qemu-system-riscv$(BITS) -M virt -m 512M -nographic \\"; \
	  echo "    -bios fw_dynamic.bin \\"; \
	  echo "    -kernel Image \\"; \
	  echo "    -initrd initramfs.cpio.gz \\"; \
	  echo "    -append \"root=/dev/ram rdinit=/init console=ttyS0 earlycon=sbi\""; \
	  echo '```'; \
	  echo ""; \
	  echo "### 3. Spike — ISA simulator"; \
	  echo ""; \
	  echo '```bash'; \
	  echo "spike --isa=$(RISCV_ISA) -m512 fw_payload.elf"; \
	  echo '```'; \
	  echo ""; \
	  echo "## Notes"; \
	  echo ""; \
	  echo "- FPU is disabled; your toolchain should target \`rv$(BITS)imac\` / \`$(RISCV_ABI)\`."; \
	  echo "- Press **Ctrl-A X** to quit QEMU."; \
	  echo "- Spike requires riscv-isa-sim with rv$(BITS) support."; \
	  echo "  Build guide: <https://github.com/riscv-software-src/riscv-isa-sim>"; \
	) > $(RELEASE_STAGING)/README.md
	tar -czf $(RELEASE_TARBALL) -C $(PWD_DIR)/dist $(RELEASE_NAME)
	@echo "Package ready: $(RELEASE_TARBALL)"

package_all:
	$(MAKE) BITS=32 package
	$(MAKE) BITS=64 package
	@echo ""
	@echo "Packages ready:"
	@echo "  $(PWD_DIR)/dist/linux-riscv-rv32-v$(KERNEL_VERSION).tar.gz"
	@echo "  $(PWD_DIR)/dist/linux-riscv-rv64-v$(KERNEL_VERSION).tar.gz"

# ---------------------------------------------------------------------------
# GitHub Release  (requires the 'gh' CLI: https://cli.github.com)
#
# Usage:
#   make github_release                    # tag = v<KERNEL_VERSION>
#   make github_release TAG=v6.18.15-rc1  # custom tag
#
# Both rv32 and rv64 tarballs must exist (run 'make package_all' first).
# ---------------------------------------------------------------------------

TAG ?= v$(KERNEL_VERSION)

github_release:
	@command -v gh >/dev/null 2>&1 || \
		(echo "ERROR: 'gh' CLI not found. Install from https://cli.github.com" && false)
	@test -f $(PWD_DIR)/dist/linux-riscv-rv32-v$(KERNEL_VERSION).tar.gz || \
		(echo "ERROR: rv32 tarball not found. Run 'make package_all' first." && false)
	@test -f $(PWD_DIR)/dist/linux-riscv-rv64-v$(KERNEL_VERSION).tar.gz || \
		(echo "ERROR: rv64 tarball not found. Run 'make package_all' first." && false)
	@echo "--- Creating GitHub Release $(TAG) ---"
	gh release create $(TAG) \
		$(PWD_DIR)/dist/linux-riscv-rv32-v$(KERNEL_VERSION).tar.gz \
		$(PWD_DIR)/dist/linux-riscv-rv64-v$(KERNEL_VERSION).tar.gz \
		--title "Linux $(KERNEL_VERSION) for RISC-V rv32/rv64imac" \
		--notes $$'Pre-built Linux $(KERNEL_VERSION) kernels for RISC-V rv32imac and rv64imac (no FPU).\n\nSee README.md inside each tarball for boot instructions (QEMU / Spike).'
	@echo "Release $(TAG) published."

clean_packages:
	rm -rf $(PWD_DIR)/dist
	@echo "dist/ removed."

clean:
	rm -rf linux build32 build64 \
		initramfs32 initramfs64 initramfs32.cpio.gz initramfs64.cpio.gz \
		opensbi opensbi-build32 opensbi-build64 \
		payload/build

clean_spike:
	rm -rf spike spike-build

clean_buildroot:
	rm -rf buildroot32 buildroot64

.PHONY: all \
        linux opensbi buildroot spike_src \
        build_linux \
        build_init make_initramfs_simple make_initramfs_buildroot install_initramfs \
        build_opensbi build_opensbi_with_kernel build_spike \
        test_qemu test_qemu_kernel test_spike \
        build_all clean clean_buildroot clean_spike \
        package package_all github_release clean_packages

