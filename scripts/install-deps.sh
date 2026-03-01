#!/usr/bin/env bash
# install-deps.sh — Install all host dependencies for linux-build
# Usage: bash scripts/install-deps.sh
set -euo pipefail

sudo apt-get update -qq

# Cross-compiler toolchain (required on all hosts; also needed on riscv64 for 32-bit builds)
sudo apt-get install -y gcc-riscv64-linux-gnu

# Kernel build dependencies
sudo apt-get install -y bc bison flex libelf-dev libssl-dev

# initramfs utilities
sudo apt-get install -y cpio gzip

# OpenSBI / Spike build dependency
sudo apt-get install -y device-tree-compiler

# Spike build dependencies
sudo apt-get install -y autoconf automake libmpc-dev libmpfr-dev libgmp-dev gawk

# QEMU
sudo apt-get install -y qemu-system-misc

echo "All dependencies installed successfully."
