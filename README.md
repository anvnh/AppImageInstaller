# AppImage Installer and Uninstaller

A lightweight, distribution-agnostic utility for integrating .AppImage applications into a user’s desktop environment.
It installs or removes applications cleanly without requiring root access.

# Features:

- Portable installation in ~/Applications
- Automatic creation of .desktop launchers
- Optional Wayland IME support for Electron apps
- Automatic icon extraction (SVG/PNG/XPM/ICO/WEBP)
- Desktop and icon cache updates (GNOME, KDE, etc.)
- Clean removal of all related files

# Dependencies

## Arch Linux

```sh
sudo pacman -S --needed \
bash coreutils grep sed awk findutils \
desktop-file-utils shared-mime-info \
imagemagick bsdtar fzf \
gtk-update-icon-cache \
plasma-workspace \
fuse2
```

# Installation

Clone this repository and ensure both scripts are executable:

```sh
git clone https://github.com/anvnh/AppImageInstaller.git
cd AppImageInstaller
chmod +x install.sh uninstall.sh
```
