---
tags: [homelab, network, storage]
---

# Remote Server Access via File Managers (SFTP)

Canonical and unified methodology for accessing remote filesystems on homelab servers (`kuaray`, `kavure`) from **Psicopompo**, simultaneously compatible with both **Dolphin** (KDE Plasma) and **Cosmic Files** (COSMIC Desktop).

## Architectural Principles

1. **Native SFTP Protocol Standard:** Do not use manually mounted `sshfs` or proprietary protocol abstractions (`remote:/`). The `sftp://` scheme is native, asynchronous, supports automatic reconnection, and respects connection directives in `~/.ssh/config`.
2. **Transparent Public-Key Authentication:**
   - `~/.ssh/config` defines explicit aliases `Host kuaray` and `Host kavure` backed by an Ed25519 identity key (`~/.ssh/id_ed25519`).
   - The user `ssh-agent` transparently negotiates sessions without manual passphrase entry.
3. **Multi-Desktop Compatibility Standard:**
   - **Cosmic Files (GIO/GVFS):** Parses bookmarks from `~/.config/gtk-3.0/bookmarks` and mounts endpoints at `/run/user/1000/gvfs/sftp:host={host}` via `gio mount sftp://{host}/`.
   - **Dolphin (KIO):** Parses bookmark definitions from `~/.local/share/user-places.xbel` using the XML structure `<bookmark href="sftp://{host}/">`.

## File Manager Configuration

### 1. Cosmic Files (`~/.config/gtk-3.0/bookmarks`)

```text
sftp://kuaray/ Kuaray (Root)
sftp://kavure/ Kavure (Root)
```

Manual on-demand mounting via CLI (for scripting or automated workflows):
```bash
gio mount sftp://kuaray/
gio mount sftp://kavure/
```

### 2. Dolphin (`~/.local/share/user-places.xbel`)

Entries are registered using the canonical `sftp://` scheme:
```xml
<bookmark href="sftp://kuaray/">
  <title>Kuaray (Root)</title>
  <info>
    <metadata owner="http://freedesktop.org">
      <bookmark:icon name="folder-remote"/>
    </metadata>
  </info>
</bookmark>
<bookmark href="sftp://kavure/">
  <title>Kavure (Root)</title>
  <info>
    <metadata owner="http://freedesktop.org">
      <bookmark:icon name="folder-remote"/>
    </metadata>
  </info>
</bookmark>
```

## Maintenance & Sanitization Performed (2026-10-04)

- Deprecated and removed legacy `remote:/kuaray-root` entries from Dolphin.
- Purged stale `fuse.sshfs` mount bookmarks referencing `/home/edu/kuaray` from `user-places.xbel`.
- Enrolled canonical `sftp://kuaray/` and `sftp://kavure/` bookmarks across all desktop managers.

## Automated Session Login Mounting & Recovery (2026-10-06)

To guarantee that remote shares appear automatically as mounted **Network Drives** inside Cosmic Files and Dolphin immediately upon graphical login:

1. **Mount Automation Script:** `~/.local/bin/homelab-sftp-mount.sh`
   - Checks whether the target endpoint is already mounted (`gio mount -l`).
   - If missing, mounts via `gio mount sftp://{host}/` with a 5-second defensive timeout in case the host is currently powered down.
2. **User Systemd Service:** `~/.config/systemd/user/homelab-sftp-mount.service` (`Type=oneshot`).
3. **Periodic Health Check Timer:** `~/.config/systemd/user/homelab-sftp-mount.timer`
   - Triggers 30 seconds following graphical session initialization and repeats every 5 minutes.
   - Ensures that if an offline server (such as `kuaray`) boots after Psicopompo has already initialized, it is discovered and mounted automatically the moment it becomes reachable.
