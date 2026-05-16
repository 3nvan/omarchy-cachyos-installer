# Omarchy on CachyOS

A shell script that installs DHH's Omarchy configuration on top of CachyOS without breaking either.

![Shell](https://img.shields.io/badge/shell-bash-blue)
![License](https://img.shields.io/badge/license-AGPLv3-red)

## What This Does

Omarchy is an opinionated Hyprland desktop setup focused on simplicity and productivity. CachyOS is a performance-optimized Arch Linux distribution. This script bridges the two.

The script:
1. Clones Omarchy from GitHub
2. Patches the install scripts for CachyOS compatibility
3. Runs the Omarchy installer on your CachyOS system

## What You Need to Do First

This script does **not** install CachyOS. Install CachyOS with these specific choices:

- **File System:** BTRFS (with Snapper)
- **Shell:** Fish (default on CachyOS)
- **Desktop:** Minimal (no DE) or CachyOS Hyprland (skips GNOME/KDE)
- **NVIDIA:** Install CachyOS recommended drivers

## Installation

```bash
git clone https://github.com/3nvan/omarchy-cachyos-installer.git
cd omarchy-cachyos-installer/bin
chmod +x install-omarchy-on-cachyos.sh
./install-omarchy-on-cachyos.sh
```

Review the script first before running. Standard disclaimer applies.

## What Gets Patched

The script resolves conflicts between CachyOS and Omarchy defaults:

| Conflict | Resolution |
|---|---|
| AUR helper (Paru vs Yay) | Installs Yay |
| Shell (Fish vs Bash) | Keeps Fish as default |
| TLDR (Tealdeer vs tldr) | Keeps Tealdeer |
| Mise activate | Fish-compatible command |
| Display manager | Installs Plymouth/Hyprland login if none detected |
| NVIDIA drivers | Skips Omarchy driver install |
| Full disk encryption | Respects user's CachyOS choice |

## Project Structure

```
omarchy-cachyos-installer/
├── bin/
│   └── install-omarchy-on-cachyos.sh  # The installer
├── LICENSE
└── README.md
```

## Legal

**Provided "as is."** No warranty. Use at your own risk. Always backup your system before running install scripts.

## License

GNU Affero General Public License v3 (AGPL) - See LICENSE file for details.
