# Build target bitness: 32 or 64 (default: 32, inherited from parent Makefile)
BITS ?= 32

# Cross-compiler prefix (default: riscv64-linux-gnu-, inherited from parent Makefile)
CROSS_COMPILE ?= riscv64-linux-gnu-

CC := $(CROSS_COMPILE)gcc

ifeq ($(BITS),64)
  CFLAGS := -march=rv64imac_zicsr_zifencei -mabi=lp64 -nostdlib
else
  CFLAGS := -march=rv32ima_zicsr_zifencei_zicntr -mabi=ilp32 -nostdlib
endif

LDFLAGS := -Wl,-e,_start -static

init_loop:
	$(CC) $(CFLAGS) $(LDFLAGS) -o init init_loop.c $(LDFLAG)

install: init
	cp init ../initramfs

clean:
	rm -f init

.PHONY: init_loop install clean
