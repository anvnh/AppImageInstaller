Run in NixOS without having to install dependencies to system:

```sh
nix-shell -p bash coreutils gnugrep gnused gawk findutils \
desktop-file-utils shared-mime-info imagemagick libarchive fzf \
gtk3 kdePackages.kservice fuse appimage-run --run ./lutils.sh
```
