---
tags: [homelab, guide, tutorial, desktop]
created: 2026-09-25
---

# Yazi Operations Guide — Terminal File Manager (psicopompo)

This guide documents the usage, architecture, and keybindings of **Yazi** on CachyOS/Hyprland with Noctalia, replacing Dolphin as the default system file manager.

## Why Yazi?

- **Written in Rust:** Asynchronous, non-blocking, and highly resource-efficient (<30 MB RAM in active use, 0% CPU at idle).
- **No Background Daemons:** Eliminates reliance on heavy desktop indexing services (`baloo`, `kiod6`).
- **Hyprland Integration:** Spawned instantly in a floating centered window via global shortcut (`Super + E`).
- **Native Previews:** Built-in high-performance previews for source code (`bat`), images and videos (`ffmpegthumbnailer` + `chafa`), documents (`pdftoppm`), and archives (`7z`).

---

## Window Control & Spawning

| Action | Keybinding / Command | Description |
|---|---|---|
| **Launch Yazi** | `Super + E` | Spawns Yazi in a centered floating Kitty window |
| **Quit** | `q` | Closes Yazi cleanly |
| **Exit to Sub-shell** | `_` (underscore) | Spawns a sub-shell within the current active directory |
| **Force Close** | `Super + Q` | Closes the window via standard Hyprland window manager kill |

---

## Quick Navigation (Jump Bookmarks)

Press **`g`** followed by the target key to jump to system paths:

### Local Disks & Obsidian Vault
- **`g` `n`** $\rightarrow$ `/mnt/NVME_PCI` (Primary NVMe work disk)
- **`g` `a`** $\rightarrow$ `/mnt/NVME_PCI/agentic-ai` (Obsidian Vault / Core Projects)
- **`g` `l`** $\rightarrow$ `/mnt/NVME_PCI/homelab` (Homelab repositories and Docker Compose trees)
- **`g` `s`** $\rightarrow$ `/mnt/SSD_SATA` (Secondary SATA SSD)
- **`g` `H`** (Shift+H) $\rightarrow$ `/mnt/HDD_SATA` (Local SATA HDD)
- **`g` `b`** $\rightarrow$ `/mnt/BACKUP` (NAS backup mount)
- **`g` `G`** (Shift+G) $\rightarrow$ `~/Google_Drive` (Rclone-mounted cloud storage)

### Remote Cluster Nodes (Tailnet)
- **`g` `k`** $\rightarrow$ `~/Remote/kuaray` (Kuaray SFTP/remote mount)
- **`g` `v`** $\rightarrow$ `~/Remote/kavure` (Kavure SFTP/remote mount)

### Default User Directories
- **`g` `h`** $\rightarrow$ `~` (Home directory)
- **`g` `d`** $\rightarrow$ `~/Downloads` (Downloads)
- **`g` `c`** $\rightarrow$ `~/.config` (Configuration files)
- **`g` `t`** $\rightarrow$ System Trash bin

---

## Movement & Cursor Navigation (Vim-style)

- **`k`** or **`↑`**: Move cursor up.
- **`j`** or **`↓`**: Move cursor down.
- **`h`** or **`←`**: Navigate to parent directory.
- **`l`** or **`→`** or **`Enter`**: Enter directory or open selected file.
- **`g` `g`**: Jump to top of directory listing.
- **`G`**: Jump to bottom of directory listing.

---

## Multi-file Selection

1. **Item Toggle (`Space`):**
   - Press `Space` on a target file to select it and advance the cursor.
   - Pressing `Space` again deselects the item.
2. **Visual Block Selection (`v`):**
   - Press **`v`** to toggle visual selection mode.
   - Move the cursor (`j`/`k` or arrows) to highlight a contiguous block of items.
   - Press `v` or `Esc` to exit visual selection.
3. **Select All (`Ctrl + A`):**
   - Selects every item in the current directory.
   - Press `Esc` to deselect all items.

---

## Interacting with External GUI Applications (Browser, Chat, Discord)

Because Yazi runs within Wayland terminal emulators (Kitty), files can be shared seamlessly with GUI windows:

### Method 1: System Clipboard (Ctrl+C / Ctrl+V — Fastest)
Modern browsers (Firefox, Chromium, Brave) and communication apps (Discord, Telegram, Slack, WhatsApp Web) accept direct file paste:
1. In Yazi, highlight files and press **`Ctrl + c`** (or `y`).
2. Focus the external application's message or upload dialog and press **`Ctrl + v`**.

### Method 2: Native Mouse Drag-and-Drop
Yazi supports native Wayland mouse drag events (`mouse_events = [ "click", "scroll", "drag" ]`):
- Click and drag files with the primary mouse button directly into external browser upload zones or desktop targets.

---

## File Operations

- **Copy:** `y` on selected items.
- **Cut / Move:** `x` on selected items.
- **Paste:** `p` into target directory.
- **Delete (Send to Trash):** `d`.
- **Permanent Delete:** `D` (Shift+D).
- **New File / Directory:** `a` (type name and press Enter; append `/` to create a folder).
- **Rename:** `r` (opens inline prompt).

---

## Search & Filtering

- **Inline Filter:** Press **`/`** and type a search pattern. Directory contents filter dynamically. Press `Esc` to reset.
- **Deep Recursive Search (`Z`):** Press **`Z`** (Shift+Z) to trigger recursive `fzf` file discovery across directory trees.
- **Text Search (grep):** Press **`s`** to search file contents recursively using `ripgrep`.

---

## Tab Management

- **`t` `t`**: Opens a new tab at current location.
- **`1`**, **`2`**, **`3`**, etc.: Switches directly to the numbered tab.
- **`w`**: Closes active tab.

---

## Configuration Paths

- **Keybindings:** [`~/.config/yazi/keymap.toml`](file:///home/edu/.config/yazi/keymap.toml)
- **General Settings:** `~/.config/yazi/yazi.toml`
- **Hyprland Launcher:** [`~/.config/hypr/config/variables.lua`](file:///home/edu/.config/hypr/config/variables.lua) (`FILE_MANAGER = "kitty --class yazi -e yazi"`)
- **Window Rules:** [`~/.config/hypr/config/windowrules.lua`](file:///home/edu/.config/hypr/config/windowrules.lua) (class `yazi` floats centered at 45% width / 55% height).
