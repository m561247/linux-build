# Kernel Configuration Details

## ISA and Config Tweaks (`build_linux`)

The base kernel build (`build_linux`) targets a plain **imac** ISA with **no FPU/D**, to
minimise CPU feature requirements.

| Config option                    | RV32         | RV64                |
| -------------------------------- | ------------ | ------------------- |
| `CONFIG_NONPORTABLE`             | enabled      | *(already default)* |
| `CONFIG_ARCH_RV64I`              | disabled     | *(already default)* |
| `CONFIG_ARCH_RV32I`              | enabled      | —                   |
| `CONFIG_FPU`                     | **disabled** | **disabled**        |
| `CONFIG_RISCV_ISA_ZAWRS`         | disabled     | disabled            |
| `CONFIG_RISCV_ISA_ZBA/ZBB/ZBC`   | disabled     | disabled            |
| `CONFIG_RISCV_ISA_ZICBOM/ZICBOZ` | disabled     | disabled            |

## Buildroot and FPU

`make_initramfs_buildroot` **re-enables `CONFIG_FPU`** after building the rootfs, because
Buildroot's default toolchain produces hard-float binaries (`lp64d` / `ilp32d` ABI).  
This means the Buildroot kernel variant effectively targets **rv32imafd / rv64imafd**,
not just `imac`.

| Variant   | `CONFIG_FPU` | Effective kernel ISA | Userspace ABI       |
| --------- | ------------ | -------------------- | ------------------- |
| Simple    | disabled     | rv32imac / rv64imac  | ilp32 / lp64        |
| Buildroot | **enabled**  | rv32imafd / rv64imafd | ilp32d / lp64d     |

> The simple `init_loop` initramfs is unaffected and stays FPU-free.
> If you switch between simple and buildroot initramfs on the same build tree,
> the kernel's `CONFIG_FPU` state will change accordingly.

## init Payload (`payload/init_loop.c`)

| Target | `-march=`                       | `-mabi=` |
| ------ | ------------------------------- | -------- |
| RV32   | `rv32ima_zicsr_zifencei_zicntr` | `ilp32`  |
| RV64   | `rv64imac_zicsr_zifencei`       | `lp64`   |

## OpenSBI ISA / XLEN

| Target | `PLATFORM_RISCV_ISA`             | `PLATFORM_RISCV_XLEN` |
| ------ | -------------------------------- | --------------------- |
| RV32   | `rv32imac_zicntr_zicsr_zifencei` | `32`                  |
| RV64   | `rv64imac_zicntr_zicsr_zifencei` | `64`                  |
