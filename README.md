# linux-build

Scripts and Makefiles for building a minimal RISC-V Linux system, including:

- Linux kernel image (`arch/riscv/boot/Image`) and kernel ELF (`vmlinux`)
- A minimal initramfs with a bare `init_loop` ELF (simple) or a full Buildroot rootfs (complex)
- OpenSBI firmware, optionally with the kernel image embedded as `FW_PAYLOAD`
- Spike (riscv-isa-sim) simulator, built from source

Both **32-bit (RV32)** and **64-bit (RV64)** targets are supported and can coexist in the same tree.  
Builds can be run from any of the following host architectures:

| Host    | 32-bit target                        | 64-bit target                         |
| ------- | ------------------------------------ | ------------------------------------- |
| x86-64  | cross-compile (`riscv64-linux-gnu-`) | cross-compile (`riscv64-linux-gnu-`)  |
| aarch64 | cross-compile (`riscv64-linux-gnu-`) | cross-compile (`riscv64-linux-gnu-`)  |
| riscv64 | cross-compile (`riscv64-linux-gnu-`) | **native** (no cross-compiler needed) |

## Prerequisites

Run the provided helper script to install all required host packages (Debian/Ubuntu):

```bash
bash scripts/install-deps.sh
```

See [scripts/install-deps.sh](scripts/install-deps.sh) for the full list of packages and comments explaining each group.

## Quick Start

### Simple initramfs (init_loop only)

```bash
# 32-bit
make linux opensbi
make BITS=32 build_linux make_initramfs_simple install_initramfs build_opensbi_with_kernel
make BITS=32 test_qemu

# 64-bit
make BITS=64 build_linux make_initramfs_simple install_initramfs build_opensbi_with_kernel
make BITS=64 test_qemu
```

### Buildroot initramfs (full userspace)

```bash
# 32-bit
make BITS=32 build_linux make_initramfs_buildroot install_initramfs build_opensbi_with_kernel
make BITS=32 test_qemu

# 64-bit
make BITS=64 build_linux make_initramfs_buildroot install_initramfs build_opensbi_with_kernel
make BITS=64 test_qemu
```

### Build and test with Spike

```bash
make build_spike                              # build Spike from source → spike-build/bin/spike
make BITS=32 build_opensbi_with_kernel
make BITS=32 test_spike                       # auto-uses spike-build/bin/spike if present
```

### Build everything (32 + 64, simple initramfs)

```bash
make build_all
```

## Build Targets

### Source acquisition

| Target      | Description                                      |
| ----------- | ------------------------------------------------ |
| `linux`     | Download and extract Linux kernel source tarball |
| `opensbi`   | Clone OpenSBI source repository                  |
| `buildroot` | Clone Buildroot source into `buildroot$(BITS)/`  |
| `spike_src` | Clone Spike (riscv-isa-sim) source into `spike/` |

### Kernel

| Target        | Description                                                 |
| ------------- | ----------------------------------------------------------- |
| `build_linux` | Configure (`defconfig` + tweaks) and build the Linux kernel |

### Initramfs

| Target                     | Description                                                           |
| -------------------------- | --------------------------------------------------------------------- |
| `build_init`               | Compile `payload/init_loop.c` into `payload/init` (bare ELF, no libc) |
| `make_initramfs_simple`    | Build `init_loop`-only initramfs → `initramfs$(BITS).cpio.gz`         |
| `make_initramfs_buildroot` | Build full Buildroot rootfs → `initramfs$(BITS).cpio.gz`              |
| `install_initramfs`        | Set `CONFIG_INITRAMFS_SOURCE` in `.config` and rebuild kernel Image   |

### Firmware

| Target                      | Description                                                 |
| --------------------------- | ----------------------------------------------------------- |
| `build_opensbi`             | Build OpenSBI generic platform firmware (no kernel payload) |
| `build_opensbi_with_kernel` | Build OpenSBI with kernel `Image` embedded as `FW_PAYLOAD`  |
| `build_spike`               | Build Spike simulator from source into `spike-build/`       |

### Test

| Target             | Description                                                                               |
| ------------------ | ----------------------------------------------------------------------------------------- |
| `test_qemu`        | Boot `fw_payload.bin` (all-in-one firmware) in QEMU                                       |
| `test_qemu_kernel` | Boot `fw_dynamic.bin` + separate kernel Image + initramfs in QEMU                         |
| `test_spike`       | Boot `fw_payload.elf` in Spike (`spike-build/bin/spike` if built, else `spike` from PATH) |

### Batch / housekeeping

| Target            | Description                                                          |
| ----------------- | -------------------------------------------------------------------- |
| `build_all`       | Build Linux + simple initramfs + OpenSBI for both 32 and 64 bit      |
| `clean`           | Remove kernel, initramfs, opensbi, and payload build artefacts       |
| `clean_buildroot` | Remove Buildroot clone(s) (`buildroot32/`, `buildroot64/`)           |
| `clean_spike`     | Remove Spike source and build directories (`spike/`, `spike-build/`) |

## Variables

| Variable        | Default   | Description                                                |
| --------------- | --------- | ---------------------------------------------------------- |
| `BITS`          | `32`      | Target bitness: `32` (RV32) or `64` (RV64)                 |
| `CROSS_COMPILE` | auto      | Cross-compiler prefix, e.g. `riscv64-linux-gnu-`           |
| `QEMU_MEM`      | `512`     | QEMU guest RAM in MiB                                      |
| `QEMU_TIMEOUT`  | *(unset)* | Auto-exit QEMU after this many seconds (uses `timeout(1)`) |
| `SPIKE_MEM`     | `512`     | Spike guest RAM in MiB                                     |

`CROSS_COMPILE` auto-detection rules:
- `BITS=32`: always `riscv64-linux-gnu-` regardless of host.
- `BITS=64` on riscv64 host: empty (native build).
- `BITS=64` on any other host: `riscv64-linux-gnu-`.

Override example:
```bash
make BITS=64 CROSS_COMPILE=riscv64-unknown-linux-gnu- build_linux
```

## Architecture-specific Details

### Kernel config tweaks (`build_linux`)

Both 32-bit and 64-bit builds target a plain **imac** ISA with **no FPU/D**, to minimise CPU feature requirements.

| Config option                    | RV32         | RV64                |
| -------------------------------- | ------------ | ------------------- |
| `CONFIG_NONPORTABLE`             | enabled      | *(already default)* |
| `CONFIG_ARCH_RV64I`              | disabled     | *(already default)* |
| `CONFIG_ARCH_RV32I`              | enabled      | —                   |
| `CONFIG_FPU`                     | **disabled** | **disabled**        |
| `CONFIG_RISCV_ISA_ZAWRS`         | disabled     | disabled            |
| `CONFIG_RISCV_ISA_ZBA/ZBB/ZBC`   | disabled     | disabled            |
| `CONFIG_RISCV_ISA_ZICBOM/ZICBOZ` | disabled     | disabled            |

### init payload (`payload/init_loop.c`)

| Target | `-march=`                       | `-mabi=` |
| ------ | ------------------------------- | -------- |
| RV32   | `rv32ima_zicsr_zifencei_zicntr` | `ilp32`  |
| RV64   | `rv64imac_zicsr_zifencei`       | `lp64`   |

### OpenSBI ISA / XLEN

| Target | `PLATFORM_RISCV_ISA`             | `PLATFORM_RISCV_XLEN` |
| ------ | -------------------------------- | --------------------- |
| RV32   | `rv32imac_zicntr_zicsr_zifencei` | `32`                  |
| RV64   | `rv64imac_zicntr_zicsr_zifencei` | `64`                  |

## Output Artefacts

32-bit and 64-bit outputs are fully isolated in separate directories and can coexist.

| Path                                                       | Description                              |
| ---------------------------------------------------------- | ---------------------------------------- |
| `build32/arch/riscv/boot/Image`                            | RV32 uncompressed kernel image           |
| `build32/vmlinux`                                          | RV32 kernel ELF (with debug symbols)     |
| `build64/arch/riscv/boot/Image`                            | RV64 uncompressed kernel image           |
| `build64/vmlinux`                                          | RV64 kernel ELF (with debug symbols)     |
| `initramfs32/`                                             | RV32 initramfs staging directory         |
| `initramfs32.cpio.gz`                                      | RV32 compressed initramfs archive        |
| `initramfs64/`                                             | RV64 initramfs staging directory         |
| `initramfs64.cpio.gz`                                      | RV64 compressed initramfs archive        |
| `opensbi-build32/platform/generic/firmware/fw_payload.elf` | RV32 OpenSBI + kernel ELF                |
| `opensbi-build32/platform/generic/firmware/fw_payload.bin` | RV32 OpenSBI + kernel binary             |
| `opensbi-build32/platform/generic/firmware/fw_dynamic.bin` | RV32 OpenSBI dynamic firmware            |
| `opensbi-build64/platform/generic/firmware/fw_payload.elf` | RV64 OpenSBI + kernel ELF                |
| `opensbi-build64/platform/generic/firmware/fw_payload.bin` | RV64 OpenSBI + kernel binary             |
| `opensbi-build64/platform/generic/firmware/fw_dynamic.bin` | RV64 OpenSBI dynamic firmware            |
| `spike-build/bin/spike`                                    | Locally-built Spike RISC-V ISA simulator |

## Project Structure

```
.
├── Makefile              # Top-level build orchestration
├── README.md             # This file
├── scripts/
│   └── install-deps.sh   # Install all host build dependencies (Debian/Ubuntu)
└── payload/
    ├── Makefile          # Builds init_loop ELF (supports BITS=32 and BITS=64)
    └── init_loop.c       # Minimal init process (infinite loop, no libc)
```

## References

- [Linux Kernel][linux] — the operating system kernel built and booted by this project.
- [OpenSBI][opensbi] — RISC-V Supervisor Binary Interface firmware used as the bootloader.
- [QEMU][qemu] — machine emulator used for `test_qemu` / `test_qemu_kernel` targets.
- [Spike (riscv-isa-sim)][spike] — RISC-V ISA reference simulator used for `test_spike`.
- [Buildroot][buildroot] — embedded Linux build system used for the full rootfs initramfs.
- [RISC-V GNU Toolchain][riscv-gnu-toolchain] — cross-compiler toolchain (`riscv64-linux-gnu-`) used for all cross-compilation.

[linux]: https://www.kernel.org/
[opensbi]: https://github.com/riscv-software-src/opensbi
[qemu]: https://www.qemu.org/
[spike]: https://github.com/riscv-software-src/riscv-isa-sim
[buildroot]: https://buildroot.org/
[riscv-gnu-toolchain]: https://github.com/riscv-collab/riscv-gnu-toolchain
