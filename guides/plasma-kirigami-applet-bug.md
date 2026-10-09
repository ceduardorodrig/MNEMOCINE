---
tags: [homelab, kde, plasma, tutorial, config, psicopompo]
---

# KDE Plasma — Broken Network and Volume Applets Post-Update (Kirigami Upstream Bug)

## The Issue

Following a system package upgrade on CachyOS (KDE Plasma) introducing **Kirigami 6.29.0** and **Qt6 6.11.2**, the system tray **Network** (`org.kde.plasma.networkmanagement`) and **Audio Volume** (`org.kde.plasma.volume`) applets fail to render: clicking the icon results in an unhandled QML popup failure ("Sorry! There was an error loading Networks.").

Journal logs report the following QML type registration conflict (`journalctl --user`):

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

Affects any Plasma component invoking `Kirigami.InlineMessage` (networking, audio volume, desktop FolderView).

## Upstream Root Cause

- Tracked upstream in **KDE Bug #508377** (Priority **HIGH**).
- Duplicates: **#524515** (Network applet, opened 2026-08-21 with identical package versions), #521692, #521572.
- Trigger: Version mismatch interaction between `kirigami 6.29` and `qt6 6.11.2`. Dynamic type identifiers drift across sessions (`IconPropertiesGroup_QMLTYPE_326` → `_355`), signaling **duplicate QML type registration** (module loaded from qrc resources vs filesystem paths).
- Network routing and daemon stacks (`NetworkManager`, `nmcli`, `nmtui`, PipeWire) remain fully operational.

## Ineffective Mitigation Attempts (Tested 2026-08-21 to 2026-08-25 on psicopompo)

| Attempt | Outcome |
|---|---|
| Purging QML caches (`~/.cache/plasmashell/qmlcache`, `kwin`, `systemsettings`, `qtshadercache-*`) + restarting plasmashell | Ineffective |
| Downgrading Kirigami 6.29 → 6.28.0 | Ineffective (identical QML hierarchy) |
| Downgrading `qt6-base` + `qt6-declarative` 6.11.2 → 6.11.1 | **ABI Cascade Failure** (`libQt6Svg.so.6` requires `QtPrivate_6_11_2`) — immediately reverted |
| Switching to vanilla Breeze global theme | Ineffective |

## The Workaround (Verified via CachyOS Community & psicopompo Testing)

Cached state inside `appletsrc` (desktop panel layout configuration) becomes poisoned, inducing plasmashell to duplicate QML module imports. Resetting the panel layout clears the duplicate type definitions:

```bash
# 1. Create timestamped backup (never delete configuration directly)
mv ~/.config/plasma-org.kde.plasma.desktop-appletsrc \
   ~/.config/plasma-org.kde.plasma.desktop-appletsrc.bak-$(date +%Y%m%d)

# 2. Restart plasmashell daemon (generates fresh default layout)
kquitapp6 plasmashell; sleep 3; kstart plasmashell

# 3. Verify zero QML applet loading errors
journalctl --user _PID=$(pgrep -x plasmashell) --no-pager | grep -c "error when loading applet"
```

- **Reversion:** Move the `.bak` file back and restart plasmashell.
- ⚠️ **Trade-off:** Panel widgets, tray pin orders, and custom monitor arrangements reset to stock defaults.
- ✅ **Preserved:** Color schemes, fonts, widget styles (`kdeglobals`), KWin window management (`kwinrc`), and global keybindings (`kglobalshortcutsrc`).
- Upstream fix will be delivered via standard distribution updates when patch lands in Kirigami/Qt6.

## References

- Upstream Tracker: https://bugs.kde.org/show_bug.cgi?id=508377
- CachyOS Discussion: discuss.cachyos.org — *Broken network and audio tray icons after update* (thread 34619)
