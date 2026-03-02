# QEMU Networking & Host Sharing

This document describes QEMU networking options for the Buildroot targets
(`test_qemu_buildroot` / `test_qemu_kernel_buildroot`).

## User-Mode Networking (NAT)

These targets pass the following to QEMU:

```
-netdev user,id=net0,hostfwd=tcp::$(SSH_PORT)-:22
-device virtio-net-device,netdev=net0
```

This creates a user-mode (NAT) network with SSH port forwarding — **no host root
privileges required**.

### SSH from the Host

```bash
ssh root@localhost -p 2222          # default password: root
```

### Inside the Guest

```sh
# Trigger DHCP manually if needed
udhcpc -i eth0

# TCP/UDP to the internet works (QEMU NAT)
wget http://example.com
wget -O - http://httpbin.org/ip
```

> **Note:** ICMP (`ping`) to external addresses does not work with user-mode networking;
> use `wget` or other TCP/UDP tools to verify connectivity.

## 9P Host Directory Share

Pass `SHARE_DIR` to share a host directory with the guest via virtio-9p:

```bash
make BITS=32 SHARE_DIR=/tmp/share test_qemu_buildroot
```

Inside the guest:

```sh
mkdir -p /mnt/host
mount -t 9p -o trans=virtio hostshare /mnt/host
```

### Read-Only Share

To prevent the guest from writing to the host directory:

```bash
make BITS=64 SHARE_DIR=/tmp/share SHARE_RO=1 test_qemu_buildroot
```

### Size-Capped Share (Loop Image)

To cap the total size a guest can consume, create a loop-file image and share
that instead of a real host directory:

```bash
# Create a 128 MB ext4 image (one-time)
dd if=/dev/zero of=share.img bs=1M count=128
mkfs.ext4 share.img

# Mount it (requires sudo)
sudo mkdir -p /mnt/share && sudo mount -o loop share.img /mnt/share

# Pass the mount-point to QEMU
make BITS=64 SHARE_DIR=/mnt/share test_qemu_buildroot

# Cleanup
sudo umount /mnt/share
```

Once the image is full the guest receives `ENOSPC` — the host filesystem is
never affected because the image file size is fixed.

## Related Variables

| Variable    | Default   | Description                                                    |
| ----------- | --------- | -------------------------------------------------------------- |
| `SSH_PORT`  | `2222`    | Host port forwarded to guest port 22                           |
| `SHARE_DIR` | *(unset)* | Host directory to share via 9P                                 |
| `SHARE_RO`  | *(unset)* | Set to `1` to mount 9P share read-only (prevents guest writes) |
| `QEMU_MEM`  | `512`     | QEMU guest RAM in MiB                                          |
