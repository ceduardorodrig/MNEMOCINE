---
tags: [homelab, tutorial, hardware, usb, fat, storage]
---

# Hollyland FAT Fix — Dirty Bit / Read-Only on FAT32 Storage Media

## The Issue

Hardware audio and video field recorders such as **Hollyland Lark Max, Lark M2, and related transceivers** record to internal flash memory or SD cards formatted in **FAT32**. Powering off these units abruptly cuts electricity to the controller without executing an orderly filesystem unmount, leaving the filesystem's **dirty bit** asserted.

The Linux kernel strictly observes this flag and mounts the volume in **read-only (`ro`)** mode to prevent subsequent metadata corruption. Users can read captured media, but **cannot delete, create, or alter files**.

Proprietary operating systems (Windows, macOS) routinely ignore unmount dirty flags on removable drives, which masks the behavior outside of Linux environments.

## Automated Architecture: UDEV + Systemd

Three integrated components resolve this automatically upon USB insertion:

| Component | Responsibility |
|---|---|
| **UDEV Rule** (`99-hollyland.rules`) | Detects device insertion by Vendor ID `3547` (Hollyland) and filesystem type `vfat` |
| **Systemd Service** (`hollyland-fix@.service`) | Triggers asynchronous repair execution outside udev device isolation namespaces |
| **Repair Script** (`hollyland-fix.sh`) | Unmounts volume, executes automated `fsck.vfat -a` repair, and clears the dirty bit |

### Execution Sequence

1. Hollyland receiver/transmitter connected over USB.
2. UDEV detects `idVendor=3547` with `vfat` payload → triggers `hollyland-fix@.service`.
3. Systemd initiates helper script:
   - Waits 2 seconds for initial auto-mount settlement;
   - Unmounts device lazily (`umount -l`);
   - Executes `fsck.vfat -a` to verify FAT tables and clear the dirty flag.
4. `udisks2` re-mounts the repaired volume in full read-write (`rw`) mode.

---

## Configuration Files

### `/usr/local/bin/hollyland-fix.sh`

```bash
#!/bin/bash
# hollyland-fix.sh — Clears FAT32 dirty bit on Hollyland audio recorders.
# Triggered asynchronously via udev -> systemd unit.

set -euo pipefail

DEVICE="/dev/$1"
LOGTAG="hollyland-fix"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $*" | logger -t "$LOGTAG"
}

log "=== Initializing repair for $DEVICE ==="

FSTYPE=$(blkid -o value -s TYPE "$DEVICE" 2>/dev/null || true)
if [ "$FSTYPE" != "vfat" ]; then
    log "  Bypassed: filesystem type=$FSTYPE (not vfat)"
    exit 0
fi

sleep 2

MOUNTPOINT=$(findmnt -n -o TARGET "$DEVICE" 2>/dev/null || true)
if [ -n "$MOUNTPOINT" ]; then
    log "  Unmounting $DEVICE from $MOUNTPOINT"
    umount -l "$DEVICE" 2>/dev/null || true
    sleep 1
fi

log "  Executing fsck.vfat -a $DEVICE"
OUTPUT=$(fsck.vfat -a "$DEVICE" 2>&1) || true
echo "$OUTPUT" | logger -t "$LOGTAG"

if echo "$OUTPUT" | grep -qi "dirty bit"; then
    log "  Dirty bit successfully cleared"
fi
if echo "$OUTPUT" | grep -qi "changes"; then
    log "  Filesystem repairs committed"
fi

log "  Completed. Automated remount will proceed in rw mode."
```

### `/etc/udev/rules.d/99-hollyland.rules`

```udev
# 99-hollyland.rules — Hollyland Lark Series Auto-Remediation
ACTION=="add", SUBSYSTEM=="block", KERNEL=="sd*", \
  ENV{ID_FS_TYPE}=="vfat", \
  ATTRS{idVendor}=="3547", \
  TAG+="systemd", ENV{SYSTEMD_WANTS}+="hollyland-fix@$kernel.service"
```

### `/etc/systemd/system/hollyland-fix@.service`

```ini
[Unit]
Description=Clear FAT32 dirty bit on Hollyland storage device (%I)
After=local-fs.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/hollyland-fix.sh %I
TimeoutStartSec=30
StandardOutput=journal
StandardError=journal
```

---

## General Linux FAT32 Optimization Best Practices

### 1. Removable USB Write Cache Throttling (`99-usb-fat-tuning.rules`)

By default, Linux permits dirty page writeback buffers to consume up to **20% of system RAM**. When transferring large video or audio takes to flash drives, file transfers report complete in UI file managers while dozens of gigabytes remain cached in volatile system memory. Premature drive detachment results in unwritten data loss.

Enforce a strict 5% buffer cap per removable drive:

```udev
# /etc/udev/rules.d/99-usb-fat-tuning.rules
ACTION=="add|change", SUBSYSTEM=="block", KERNEL=="sd*", \
  ATTR{removable}=="1", ENV{ID_FS_TYPE}=="vfat", \
  ATTR{bdi/max_ratio}="5", ATTR{bdi/strict_limit}="1"
```

### 2. Explicit Unmounting & Flushing

Always flush memory buffers or safely eject volumes prior to physical detachment:

```bash
udisksctl unmount -b /dev/sdd1
udisksctl power-off -b /dev/sdd

# Force synchronous buffer synchronization
sync /dev/sdd
```

### 3. VFAT Mount Options: `flush` vs `sync`

Ensure mount rules leverage `flush`, writing dirty blocks incrementally without the catastrophic flash memory wear and extreme latency associated with `sync`:

```bash
sudo mount -o remount,flush /run/media/edu/TARGET_DEVICE
```

---

## Manual Recovery Procedure

When operating on an unconfigured system:

```bash
# 1. Locate drive identifier
lsblk

# 2. Unmount volume
sudo umount /dev/sdd1

# 3. Repair FAT allocation table and clear dirty bit
sudo fsck.vfat -a /dev/sdd1

# 4. Detach and re-insert USB cable
```

## References

- [Linux Kernel vfat Documentation](https://www.kernel.org/doc/html/latest/filesystems/vfat.html)
- [ArchWiki — udev](https://wiki.archlinux.org/title/Udev)
- [Udisks2 Mount Architecture](https://storaged.org/doc/udisks2-api/latest/mount_options.html)
