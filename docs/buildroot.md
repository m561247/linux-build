# Buildroot Rootfs Guide

This document covers building, customising, and troubleshooting the Buildroot-based
initramfs used by this project.

> **Makefile structure:** All Buildroot-related variables and targets live in
> [`scripts/buildroot.mk`](../scripts/buildroot.mk), which is `include`-d by the top-level
> `Makefile`. You still invoke every target via `make` as usual — the split is purely for
> maintainability.

## Quick Start

```bash
# First time — full build (32-bit)
make BITS=32 build_linux make_initramfs_buildroot install_initramfs_buildroot build_opensbi_with_kernel
make BITS=32 test_qemu_buildroot

# First time — full build (64-bit)
make BITS=64 build_linux make_initramfs_buildroot install_initramfs_buildroot build_opensbi_with_kernel
make BITS=64 test_qemu_buildroot
```

## Fast Iteration After Editing `configs/buildroot.cfg`

After the initial build, you only need to rebuild Buildroot when changing packages.
The **fastest path** uses QEMU's split-load mode (separate kernel + initramfs), which
avoids re-embedding the initramfs into the kernel and rebuilding OpenSBI:

```bash
# Edit configs/buildroot.cfg, then:
make BITS=32 update_buildroot              # incremental Buildroot rebuild only
make BITS=32 test_qemu_kernel_buildroot    # boot with separate kernel + initramfs
```

If you need the all-in-one `fw_payload.bin` (for `test_qemu_buildroot` or Spike):

```bash
make BITS=32 update_buildroot_full         # Buildroot + re-embed initramfs + OpenSBI
make BITS=32 test_qemu_buildroot
```

For a completely clean Buildroot rebuild (e.g. after removing packages):

```bash
make BITS=32 make_initramfs_buildroot_clean
```

> **Incremental vs clean rebuild:** `make_initramfs_buildroot` is incremental — it only
> rebuilds packages that changed. This is much faster but may leave stale files when
> *removing* packages. Use `make_initramfs_buildroot_clean` for a guaranteed-clean rootfs.

## Customising Packages (`configs/buildroot.cfg`)

The file [`configs/buildroot.cfg`](../configs/buildroot.cfg) is a Kconfig fragment appended on
top of Buildroot's `qemu_riscv{32,64}_virt_defconfig`. It controls:

- **Output format** — cpio + gzip (ext2 disabled)
- **Extra packages** — openssh, bash, htop, strace, etc.
- **Root password** — set via `BR2_TARGET_GENERIC_ROOT_PASSWD`

Edit this file to add or remove packages, then rebuild:

```bash
make BITS=32 update_buildroot              # fast incremental path
# or
make BITS=32 make_initramfs_buildroot install_initramfs_buildroot build_opensbi_with_kernel
```

### FPU / ABI Note

`make_initramfs_buildroot` automatically re-enables `CONFIG_FPU` in the kernel after
building the Buildroot rootfs, because Buildroot's default toolchain targets the hard-float
`lp64d` / `ilp32d` ABI. The simple `init_loop` initramfs is unaffected and stays FPU-free.

## Large Rootfs and Memory Limits

When adding large packages (e.g. `BR2_PACKAGE_PYTHON3=y`), the compressed
initramfs can grow to 40–55 MB. Because `install_initramfs` **embeds** the
cpio archive into the kernel Image, the resulting Image can reach 65–80 MB.
After QEMU loads this Image the kernel must decompress the initramfs into RAM,
requiring roughly **2–3× the compressed size** of additional memory.

With the default `QEMU_MEM=512` (512 MiB) the memory map looks like:

```
0x80000000  OpenSBI firmware      (~512 KB)
0x80200000  Kernel Image           ~70 MB (with embedded initramfs)
            Kernel data structures, page tables …
            initramfs decompression buffer  ~100-150 MB
            Userspace …
0x9FFFFFFF  RAM top (512 MB)
```

This can cause an out-of-memory kernel panic or an incomplete rootfs.

### Recommended: Split-Load Mode

Keep the kernel and initramfs as separate files so the kernel Image stays small
(~10 MB) and QEMU loads the cpio archive directly without duplicating it. This
is also faster to iterate because neither the kernel nor OpenSBI needs to be
rebuilt after a Buildroot change:

```bash
make BITS=64 update_buildroot                           # incremental Buildroot rebuild
make BITS=64 QEMU_MEM=1024 test_qemu_kernel_buildroot  # split-load, 1 GiB RAM
```

### Alternative: Increase QEMU Memory

If you must use the all-in-one `fw_payload.bin` boot path, increase QEMU memory:

```bash
make BITS=64 QEMU_MEM=1024 update_buildroot_full
make BITS=64 QEMU_MEM=1024 test_qemu_buildroot
```

## Build Targets Reference

| Target                           | Description                                                                                          |
| -------------------------------- | ---------------------------------------------------------------------------------------------------- |
| `make_initramfs_buildroot`       | Build Buildroot rootfs (incremental) → `initramfs$(BITS)-buildroot.cpio.gz`; re-enables `CONFIG_FPU` |
| `make_initramfs_buildroot_clean` | Full clean Buildroot rebuild (`distclean` first — slow but guaranteed clean)                         |
| `install_initramfs_buildroot`    | Embed Buildroot cpio into kernel Image (`CONFIG_INITRAMFS_SOURCE`)                                   |
| `update_buildroot`               | Incremental Buildroot rebuild only (fastest iteration for package changes)                           |
| `update_buildroot_full`          | Buildroot rebuild + re-embed initramfs into kernel + rebuild OpenSBI                                 |
| `package_buildroot`              | Bundle Buildroot artifacts into `dist/linux-riscv-rv$(BITS)-buildroot-v*.tar.gz`                     |
| `clean_buildroot`                | Remove Buildroot clone(s) (`buildroot32/`, `buildroot64/`)                                           |

## Output Paths

Buildroot initramfs outputs are separate from the simple (init_loop) initramfs, so both
can coexist without overwriting each other:

| Path                            | Description                |
| ------------------------------- | -------------------------- |
| `initramfs32.cpio.gz`           | Simple initramfs (RV32)    |
| `initramfs32-buildroot.cpio.gz` | Buildroot initramfs (RV32) |
| `initramfs64.cpio.gz`           | Simple initramfs (RV64)    |
| `initramfs64-buildroot.cpio.gz` | Buildroot initramfs (RV64) |

### Packaging

Buildroot packages are distinct from simple initramfs packages:

```bash
# Package simple initramfs (default)
make BITS=32 package          # → dist/linux-riscv-rv32-v<ver>.tar.gz

# Package Buildroot variant
make BITS=32 package_buildroot  # → dist/linux-riscv-rv32-buildroot-v<ver>.tar.gz

# Package everything (simple + buildroot, 32 + 64)
make package_all
```
