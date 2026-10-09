---
tags: [homelab, recovery, storage, hardware, usb, kernel, psicopompo, handoff]
---

# Data Recovery — WD Elements SE 1TB (Failing Drive) — Sep–Oct 2026

> **Status:** ✅ **COMPLETED** on 02/10/2026 — **1,704 of 1,831 files recovered**  
> **(93.1% by file count · 94.6% by volume · 56.55 GB of 59.75 GB)**  
> **Delivery Target:** `/mnt/RESGATE/ENTREGA/` — Preserved original directory structures and filenames, 1 copy per file, with `_MANIFESTO.tsv` (SHA-256 hashes) and `00_RELATORIO.md`. See **§10**.  
> **Unrecoverable:** 127 files · 3.20 GB (2 iPhone `.mp4` videos = 2.2 GB, 51 JPEGs, 1 CR2 raw file, remaining were desktop configuration stubs)  
> **Dying Drive:** `WD-WX51A68876FE` — SMART **FAILED**, powered down and preserved.  
> **Host Node:** psicopompo (CachyOS, kernel 7.2.8-1-cachyos-bore) — **2 days without panics**  
> **Working Directory:** `/mnt/HDD_SATA/recuperacao-elements/` (scratch space)  
> **Detailed Log:** `RECUPERACAO_TRACKING_2026.md` in scratch workspace  

## 1. Context

External drive **WD Elements SE 1TB** (NTFS) suffering from progressive physical degradation. SMART status: **FAILED** ("failure expected in <24h"), `Raw_Read_Error_Rate = 234718`, `Reallocated_Sector_Ct = 0` (drive controller does not reallocate sectors — it **hangs** indefinitely on read attempts).

Recovery initialized originally on workstation **morfosear** and resumed on **psicopompo** (handoff documentation at `/home/edu/Downloads/HANDOFF_COMPLETO.md`).

## 2. Drive Identification (ALWAYS resolve by Serial Number — device letters drift!)

| Role | Serial Number | Filesystem Label | Filesystem | USB Port / Bus |
|---|---|---|---|---|
| **FAILING (SOURCE)** | `WD-WX51A68876FE` | MORIBUNDO-WD-WX51A68876FE | NTFS | bus 2 / 2-2 (`usb-storage` BOT) |
| **RESCUE (TARGET)** | `WD-WXW1A976UPD4` | RESGATE | ext4 | bus 2 / 2-3 |
| **SSHD-1TB** | `0123456789ABCDEF` | SSHD-1TB | ext4 | bus 2 / 2-7 (`uas`) |
| HDD SATA (Scratch) | `S1DFKB80` | HDD SATA | btrfs | Internal SATA (`/mnt/HDD_SATA`) |

> Device nodes (`sdg`, `sdh`, `sdf`) **reorder across reboots and reconnections**. Always resolve by serial: `lsblk -dn -o NAME,SERIAL,SIZE`.

## 3. Methodology (Image-First — Minimizes Drive Wear)

1. **Bitstream Image First:** Run GNU ddrescue → write sparse raw image to healthy storage; execute PhotoRec carving **on the image file** (reading the dying physical media strictly once).
2. **Mapfiles are Stateful:** Never restart recovery jobs from scratch. If 3 consecutive sessions hang at the identical offset → skip forward 256 MB (acceptable loss policy).
3. **Never** use `-a` (aggressive auto-skip) on this controller: Generated 274 false skips.
4. **Golden Rule:** Identify physical disks strictly by serial number.

## 4. Sector Map & Throughput Profile (Measured 29/09/2026)

| LBA Offset Range | Surface Condition | Read Velocity |
|---|---|---|
| 0–3 GB | Healthy (boot sector + `$MFT` @ 3.0 GB, LCN 786432) | 67–93 MB/s |
| 4–32 GB | Episodic degradation (medium read errors at 29.57 GB) | Slow |
| 32–570 GB | Good condition | Moderate |
| 570–575 GB | Healthy but slow seek response | 39–44 MB/s |
| **576–599 GB** | **DEAD ZONE / SECTOR QUAGMIRE** | ~0.26 GB / 17 min |
| **600–1000 GB** | **Healthy** (initial pass) | 88–91 MB/s |
| 625–700 GB | **Controller degradation** (hung 17s per block) | Near 0 MB/s |
| 668.96 GB | Narrow bad sector band (medium error) | — |

The handoff `rescue.map`: **658 GB recovered, 0 sectors marked as hard errors, 341 GB unattempted** — proving the controller **freezes**, rather than surface media tearing.

## 5. Key Architectural Finding: NTFS Directory Structure Intact

`ntfsls -f -l /dev/<SOURCE>1` reads directory tables (volume flagged DIRTY → requires `-f`):

```
ANNA/  Aniversario Aurora 2022/  Documentos/  Downloads/  Imagens/  JOBS/
Pedro Saliba/  Programas/  REBECA/  REF. DE ANTROVISUAL/  201202 - Cartao Camera/
IMG_1113.jpg  IMG_1120.jpg  IMG_1126.jpg  IMG_8587.CR2  _MG_8586.CR2
doc vivencia amazonica 2.0.mp4   1° corte Viv. Amaz. 2019.mp4
```

→ **Filesystem restoration with original filenames and folder hierarchies** was possible directly from the `$MFT` table region (~3 GB offset).

## 6. ⚠️ Critical Operational Constraint: Kernel Panic on USB Reset Storms

### Symptom
System experienced hard freezes; reboot was blocked until physical USB cables were disconnected.

### Root Cause — Upstream Kernel Driver NULL Pointer Dereference

```
BUG: kernel NULL pointer dereference, address: 00000000000001b8
#PF: supervisor write access in kernel mode
CPU: 1  Comm: usb-storage   Tainted: [O]=OOT_MODULE [E]=UNSIGNED_MODULE
RIP: 0010:scsi_complete+0x3f/0x270
Call Trace:
  usb_stor_control_thread+0x262/0x2d0 [usb_storage]
  kthread+0xe4/0x120 → ret_from_fork
Hardware: Dell Precision 3630 Tower · kernel 7.2.8-1-cachyos-bore
```

When the failing drive triggers a **USB error and reset storm**, after ~10–15 resets the kernel's `scsi_complete()` dereferences NULL. The kernel oops corrupts storage subsystem state → hard system freeze.

### Active Safeguards Deployed (29/09 18:35)

| # | Safeguard | Implementation |
|---|---|---|
| 1 | **SysRq Enabled** (`kernel.sysrq = 1`) | `/etc/sysctl.d/99-homelab-sysrq.conf` |
| 2 | **Hardware Watchdog** | `RuntimeWatchdogSec=30s` in `/etc/systemd/system.conf` → `intel_oc_wdt` active |
| 3 | **`reset-guard.sh` (v6)** | Watches journal continuously; on first reset storm (**3 resets / 45s**) → issues `SIGINT` + I/O drain; second storm while idle → `unbind`+`bind`; hard kills after 12s if ddrescue hangs; reapplies SCSI `timeout=5` |
| 4 | **SCSI Timeout = 5s** | `/sys/block/sdX/device/timeout` |

**Outcome:** System recovers via automated 30s hardware watchdog reset if panicked, and ddrescue resumes cleanly from its stateful mapfile.

## 7. Operational Playbook — Safe Recovery of Failing USB Media

1. **Isolation:** Identify drives strictly by serial number; keep failing drive unmounted (raw block access).
2. **Arm Protections:** `sysrq=1`, hardware watchdog (`RuntimeWatchdogSec=30s`), `reset-guard.sh`, SCSI `timeout=5`.
3. **Parse Previous Mapfiles:** Never reread sectors that have already been salvaged.
4. **Two-Pass Imaging Strategy (Rossmann / Data Recovery Lab Best Practice):**
   - **Pass 1:** `ddrescue -n` (skip scraping) — captures easy contiguous blocks and skips bad areas quickly.
   - **Pass 2:** Target remaining unread blocks with retries (`-r1`).
   Use bounded execution sessions (`timeout 120`), `-T60s`, `--skip-size`, `--sparse`. Never use aggressive `-a`.
5. **Carve from Raw Image:** PhotoRec on loop device with curated file signature families.
6. **Continuous SMART Telemetry:** Monitor `Current_Pending_Sector` every 15 minutes.
7. **Filesystem Metadata Inventory:** Extract `$MFT` via `ntfsls -R -f -l` to generate reference index of all original filenames and sizes.
8. **Deduplication:** Run `fdupes` against previously carved datasets.
9. **Scratch Clean-up:** Purge raw images upon delivery validation.

## 8. Summary of Results

### NTFS Volume Inventory
- **Indexed File Count:** 1,831 unique paths across 271 directories
- **Total Valid Payload:** **59.75 GB** (previous 64.29 GB estimate counted duplicated hardlink entries twice)
- **Primary Media:** 37.58 GB `.mov` (Canon video), 13.81 GB `.cr2` (Canon RAW), 5.14 GB `.jpg`, 4.10 GB `.mp4`

### Recovery Statistics

```
TOTAL FILES INDEXED        1,831  ·  59.75 GB
SUCCESSFULLY RECOVERED     1,704  ·  56.55 GB     93.1% file count · 94.6% volume
LOST / UNRECOVERABLE         127  ·   3.20 GB
```

| Extension | Recovered | Total |
|---|---|---|
| `.cr2` (Canon RAW) | **513** | 514 |
| `.mov` (QuickTime iPhone) | **237** | 242 |
| `.jpg` | **917** | 968 |
| `.mp4` | **24** | 29 |
| `.png` | 11 | 13 |
| Configuration Stubs (`.ini`, `.txt`, `.db`, `.lnk`) | 0 | 38 |

Delivery organized at `/mnt/RESGATE/ENTREGA/` with verified SHA-256 manifest.

### USB Transport Layer Failure

Throughput crashes were tracked to USB controller resets rather than surface magnetic degradation:
The xHCI USB host controller reset port `2-2` continuously every 36.86 seconds. Once power-cycled, throughput dropped to 0.05 MB/s with ddrescue projecting 19 days for remaining 27 GB — accepted as final unrecoverable boundary.

### Signature Validation Bug Resolution

Initial QuickTime carving showed 58 missing `.mov` files because the validator expected `ftyp` box headers. iPhone QuickTime files utilize `wide` + `mdat` box structures (`00 00 00 08 'wide' ...`). Updating the signature validator recovered 53 additional videos (9.5 GB), lifting final recovery to 237 of 242 videos.

## 9. References

- Scratch Tracking: `/mnt/HDD_SATA/recuperacao-elements/RECUPERACAO_TRACKING_2026.md`
- Original Handoff: `/home/edu/Downloads/HANDOFF_COMPLETO.md`
- [`mnemocine/recovery/disaster-recovery.md`](disaster-recovery.md)
- [`mnemocine/backups/strategy.md`](../backups/strategy.md)
