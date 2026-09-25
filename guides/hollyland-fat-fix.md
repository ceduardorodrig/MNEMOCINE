---
tags: [homelab, tutorial, hardware, usb, fat, storage]
---

# Hollyland FAT Fix — Dirty Bit / Read-Only on FAT32 Devices

## The Problem

Audio/video recorders such as the **Hollyland Lark Max, Lark M2 and similar** use an SD card or internal memory formatted as **FAT32**. When the device is powered off, it simply cuts the power — it **does not unmount the filesystem**. That leaves the so-called **dirty bit** (unclean unmount bit) set on FAT32.

Linux **respects that bit** and mounts the device as **read-only (`ro`)** to avoid data corruption. The result: you can read the files, but **you cannot delete, create or edit anything**.

Windows and Mac **ignore** that bit and mount read-write as usual — which is why the problem only shows up on Linux.

## The Solution — Full Automation with UDEV + Systemd

Three components work together to solve this **automatically** every time you connect a Hollyland:

| Component | Function |
|---|---|
| **udev rule** (`99-hollyland.rules`) | Detects the device by vendor ID `3547` (Hollyland) + vfat filesystem |
| **Systemd service** (`hollyland-fix@.service`) | Runs the script asynchronously (does not block boot) |
| **Script** (`hollyland-fix.sh`) | Unmounts, runs `fsck.vfat -a` (auto, non-interactive) and clears the dirty bit |

### Flow

1. You plug the Hollyland into USB
2. Udev detects: `idVendor=3547` + `vfat` → triggers the systemd service
3. The service runs the script, which:
   - Waits 2 seconds (for the initial mount to finish)
   - Unmounts the device (lazy unmount)
   - Runs `fsck.vfat -a` → clears the dirty bit
4. The system (udisks2) **automatically remounts** as `rw`

### Why not use `RUN` in udev?

udev's `RUN` executes in an isolated namespace — mounts made there are not visible to the rest of the system. The correct approach is `TAG+="systemd"` + `ENV{SYSTEMD_WANTS}`, which triggers a systemd service in the global namespace.

---

## System Files

### `/usr/local/bin/hollyland-fix.sh`

```bash
#!/bin/bash
# hollyland-fix.sh — Limpa dirty bit FAT32 em dispositivos Hollyland
# Acionado por udev → systemd service quando um dispositivo Hollyland
# com filesystem vfat é conectado.

set -euo pipefail

DEVICE="/dev/$1"
LOGTAG="hollyland-fix"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $*" | logger -t "$LOGTAG"
}

log "=== Iniciando fix para $DEVICE ==="

FSTYPE=$(blkid -o value -s TYPE "$DEVICE" 2>/dev/null || true)
if [ "$FSTYPE" != "vfat" ]; then
    log "  Ignorado: tipo=$FSTYPE (não é vfat)"
    exit 0
fi

sleep 2

MOUNTPOINT=$(findmnt -n -o TARGET "$DEVICE" 2>/dev/null || true)
if [ -n "$MOUNTPOINT" ]; then
    log "  Desmontando $DEVICE de $MOUNTPOINT"
    umount -l "$DEVICE" 2>/dev/null || true
    sleep 1
fi

log "  Rodando fsck.vfat -a $DEVICE"
OUTPUT=$(fsck.vfat -a "$DEVICE" 2>&1) || true
echo "$OUTPUT" | logger -t "$LOGTAG"

if echo "$OUTPUT" | grep -qi "dirty bit"; then
    log "  dirty bit removido com sucesso"
fi
if echo "$OUTPUT" | grep -qi "changes"; then
    log "  alterações foram escritas no filesystem"
fi

log "  Finalizado. A remontagem automática deve ocorrer em rw."
```

### `/etc/udev/rules.d/99-hollyland.rules`

```
# 99-hollyland.rules — Hollyland Lark Max / Lark / Wireless Mic
#
# Match por vendor 3547 cobre TODOS os produtos Hollyland
# (Lark Max, Lark M2, Lark M1, Lark 150, etc).
#
# Filtros adicionais:
#   - SUBSYSTEM=="block" → só dispositivos de bloco
#   - ENV{ID_FS_TYPE}=="vfat" → só FAT32
#   - ATTRS{idVendor}=="3547" → só Hollyland

ACTION=="add", SUBSYSTEM=="block", KERNEL=="sd*", \
  ENV{ID_FS_TYPE}=="vfat", \
  ATTRS{idVendor}=="3547", \
  TAG+="systemd", ENV{SYSTEMD_WANTS}+="hollyland-fix@$kernel.service"
```

### `/etc/systemd/system/hollyland-fix@.service`

```ini
[Unit]
Description=Clear FAT32 dirty bit on Hollyland device (%I)
Documentation=https://github.com/usbids/usbids/blob/master/usb.ids
After=local-fs.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/hollyland-fix.sh %I
TimeoutStartSec=30
StandardOutput=journal
StandardError=journal
```

---

## General Best Practices for FAT32 on Linux

### 1. Limit the USB Write Cache (`99-usb-fat-tuning.rules`)

By default, Linux uses up to **20% of RAM** as a write cache (dirty pages). This means that when you copy a file to a flash drive, the "copy" shows as **done before the data has actually reached the device** — it is still sitting in the RAM cache. If you remove the device at that moment, the data is lost.

This udev rule limits the cache to **5% per removable USB device** and enables `strict_limit`:

```
# /etc/udev/rules.d/99-usb-fat-tuning.rules
ACTION=="add|change", SUBSYSTEM=="block", KERNEL=="sd*", \
  ATTR{removable}=="1", ENV{ID_FS_TYPE}=="vfat", \
  ATTR{bdi/max_ratio}="5", ATTR{bdi/strict_limit}="1"
```

**Effect:** the maximum cache for each USB drops from 20% to 5% of RAM. Data reaches the device faster. Writes are still `async` (performance is not as drastically affected as with `sync`).

### 2. Eject / Sync

Whenever possible, eject the device before removing it:

```bash
# Via comando
udisksctl unmount -b /dev/sdd1
udisksctl power-off -b /dev/sdd

# Ou via Nautilus / qualquer file manager → "Eject" / "Unmount"
```

If you need to guarantee that the data made it to disk:

```bash
sync
# ou para um dispositivo específico
sync /dev/sdd
```

### 3. The `flush` Mount Option

`flush` is a vfat mount option that makes data be flushed to disk earlier than normal (without being as aggressive as `sync`). By default, udisks2 already mounts vfat with `flush` — you can verify with:

```bash
mount | grep vfat
```

If for some reason you are not using `flush`, add:

```bash
sudo mount -o remount,flush /run/media/edu/SEU_DISPOSITIVO
```

> ⚠️ **Do not use `sync`** for vfat — it makes writes extremely slow and shortens the lifespan of flash media.

### 4. When None of This Works

If the device stays `ro` even after the dirty bit has been cleared:

1. Check whether there is a **physical write-protect switch** on the SD card / adapter
2. Check for **hardware errors**:
   ```bash
   sudo dmesg | grep -i "i/o error\|buffer I/O\|device error"
   ```
3. The card may be **at the end of its useful life** — NAND controllers force `ro` mode when the media is no longer reliable. Replace the card.

---

## Installation / Reinstallation

If you ever ~~reformat the PC~~ ~~switch distro~~ ~~blow everything up~~ and need to reapply:

```bash
# 1. Copiar script
sudo cp /tmp/hollyland-fix.sh /usr/local/bin/hollyland-fix.sh
sudo chmod +x /usr/local/bin/hollyland-fix.sh

# 2. Copiar regras udev
sudo cp /tmp/99-hollyland.rules /etc/udev/rules.d/
sudo cp /tmp/99-usb-fat-tuning.rules /etc/udev/rules.d/

# 3. Copiar service
sudo cp /tmp/hollyland-fix@.service /etc/systemd/system/

# 4. Recarregar tudo
sudo udevadm control --reload-rules
sudo systemctl daemon-reload

# 5. Testar (opcional — com dispositivo conectado)
sudo journalctl -f -u hollyland-fix@*
```

### Manual Recovery (no automation)

If the system is not configured and you need to do it by hand:

```bash
# 1. Identificar o dispositivo
lsblk

# 2. Desmontar
sudo umount /dev/sdd

# 3. Rodar fsck
sudo fsck.vfat -a /dev/sdd

# 4. Remover e reconectar o dispositivo
```

---

## References

- [Linux Kernel — vfat documentation](https://www.kernel.org/doc/html/latest/filesystems/vfat.html)
- [USB ID Repository — Hollyland](https://github.com/usbids/usbids)
- [Arch Wiki — udev](https://wiki.archlinux.org/title/Udev)
- [Arch Wiki — FAT](https://wiki.gentoo.org/wiki/FAT)
- [Udisks2 mount options](https://storaged.org/doc/udisks2-api/latest/mount_options.html)
