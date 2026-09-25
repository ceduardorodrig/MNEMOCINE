---
tags: [homelab, kde, plasma, tutorial, config, psicopompo]
---

# KDE Plasma — Network and Volume applets broken after an update (Kirigami bug)

## The Problem

After a CachyOS (KDE Plasma) update that brought in **kirigami 6.29.0** and **qt6 6.11.2**, the **Network** (`org.kde.plasma.networkmanagement`) and **Volume** (`org.kde.plasma.volume`) applets in the tray stop loading: clicking the icon does not open the popup ("Sorry! There was an error loading Networks.").

QML errors in the journal (`journalctl --user`):

```
main.qml:60:25: Type PopupDialog unavailable
PopupDialog.qml:110:22: Type ConnectionListPage unavailable
ConnectionListPage.qml:26:5: Type Kirigami.InlineMessage unavailable
InlineMessage.qml:14:1: Type KT.InlineMessage unavailable
templates/InlineMessage.qml:187:51: Cannot assign object of type
  "Primitives.IconPropertiesGroup" to property of type
  "IconPropertiesGroup_QMLTYPE_*" as the former is neither the same as
  the latter nor a sub-class of it.
```

This affects **any** component that uses `Kirigami.InlineMessage` (network, volume, the desktop FolderView), not just the network applet.

## Root cause (upstream)

- Bug **KDE #508377** (priority **HIGH**, open since 08/2025, **no fix**).
- Duplicates: **#524515** (network applet, opened 21/08/2026 with the SAME versions as this homelab), #521692, #521572.
- Trigger: the `kirigami 6.29` + `qt6 6.11.2` combination. The type ID changes between sessions (`IconPropertiesGroup_QMLTYPE_326` → `_355`) — the signature of **QML type duplication** (module loaded via qrc vs disk).
- It is not a user configuration bug, nor a theme bug. The network itself works (`nmcli`/`nmtui`).

## What does NOT fix it (tested 21-25/08/2026 on psicopompo)

| Attempt | Result |
|---|---|
| Clear QML caches (`~/.cache/plasmashell/qmlcache`, `kwin`, `systemsettings`, `qtshadercache-*`) + restart plasmashell | Does not fix it |
| Downgrade kirigami 6.29 → 6.28.0 | Does not fix it (identical QML structure) |
| Downgrade qt6-base + qt6-declarative 6.11.2 → 6.11.1 | **ABI spiral** (`libQt6Svg.so.6` requires `QtPrivate_6_11_2`) — reverted |
| Switch to a pure Breeze theme + clear caches | Does not fix it |

## The Fix (workaround confirmed on the CachyOS forum + validated here)

The `appletsrc` (the desktop/panel layout config) gets "poisoned" and makes plasmashell re-inject the QML type duplication. **Resetting the layout fixes it.**

```bash
# 1. Backup (reversível — NUNCA usar rm direto)
mv ~/.config/plasma-org.kde.plasma.desktop-appletsrc \
   ~/.config/plasma-org.kde.plasma.desktop-appletsrc.bak-$(date +%Y%m%d)

# 2. Reiniciar o shell (gera layout padrão novo)
kquitapp6 plasmashell; sleep 3; kstart plasmashell

# 3. Verificar (deve dar 0)
journalctl --user _PID=$(pgrep -x plasmashell) --no-pager | grep -c "error when loading applet"
```

- **Undo:** `mv` the `.bak` back + restart plasmashell.
- ⚠️ **Removes ALL panel/widget customizations** (per the forum author): you lose the layout and have to rebuild the widgets by hand. The backup lets you rebuild with parity (widget/sensor map).
- ✅ **Preserved:** theme/colors/fonts/widget style (`kdeglobals`), kwin (`kwinrc`), shortcuts (`kglobalshortcutsrc`) — `appletsrc` only holds panel/widget layout.
- The fix author on the forum noted that the **definitive fix will come in a package update** (wait for kirigami/plasma/qt6 to fix #508377).

## Applying it on this homelab

- **Host:** psicopompo (CachyOS KDE — Catppuccin + Klassy theme).
- **Date:** 25/08/2026. Fix applied successfully; backup deleted after confirmation; layout being rebuilt manually.
- **Tracking:** https://bugs.kde.org/show_bug.cgi?id=508377 — once it is resolved, a normal update restores everything (no reset needed).
- **Source forum:** discuss.cachyos.org — *Broken network and audio tray icons after update* (thread 34619).
