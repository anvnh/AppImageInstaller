#!/usr/bin/env bash
set -euo pipefail

# === Locate tool directories ===
BASE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="${BASE_DIR}/AppImageInstaller"
IME_DIR="${BASE_DIR}/DesktopIMEHelper"

APP_INSTALL="${APP_DIR}/install.sh"
APP_UNINSTALL="${APP_DIR}/uninstall.sh"
IMECTL="${IME_DIR}/bin/imectl"

pause() { read -rp "Press Enter to continue..."; }
clear_screen() { command -v clear >/dev/null && clear || printf "\n%.0s" {1..30}; }

# --- helper: list .desktop with optional filter, fzf-aware ---
list_desktops() {
  clear_screen
  read -rp "Filter (regex, empty = all): " pat
  local U="${XDG_DATA_HOME:-$HOME/.local/share}/applications" S="/usr/share/applications"
  # build list: filename, Name=, Exec=
  mapfile -t rows < <(
    for d in "$U" "$S"; do
      [[ -d $d ]] || continue
      find "$d" -maxdepth 1 -type f -name "*.desktop" -print0 \
      | xargs -0 -I{} awk -v f="{}" -F= '
          BEGIN{name=""; exec=""}
          /^Name=/ && name==""{name=substr($0,6)}
          /^Exec=/ && exec==""{exec=substr($0,6)}
          END{
            n=f; sub(/^.*\//,"",n)
            printf "%-48s | %-40s | %s | %s\n", n, name, exec, f
          }'
    done | sort -f
  )

  if [[ -n "${pat}" ]]; then
    # case-insensitive match on filename, Name, or Exec
    rows=( $(printf "%s\n" "${rows[@]}" | awk -v IGNORECASE=1 -v p="$pat" -F'|' '
      $0 ~ p || $1 ~ p || $2 ~ p || $3 ~ p {print}') )
  fi

  if command -v fzf >/dev/null 2>&1; then
    printf "%s\n" "FILENAME                                         | NAME                                     | EXEC | PATH"
    sel="$(printf "%s\n" "${rows[@]}" | fzf --ansi --with-nth=1,2,3 --prompt="Select (Enter to view Exec, Ctrl-C to exit) > " || true)"
    [[ -z "$sel" ]] && { pause; return; }
    path="$(awk -F'|' '{print $4}' <<<"$sel" | xargs)"
    echo
    echo "File: $path"
    echo "Exec: $(awk -F= '/^Exec=/{print substr($0,6); exit}' "$path")"
  else
    printf "%s\n" "FILENAME                                         | NAME                                     | EXEC | PATH"
    printf "%s\n" "${rows[@]}"
  fi
  echo
  pause
}

main_menu() {
  clear_screen
  cat <<EOF
=========================
   Linux Utilities Menu
=========================
1) AppImage Installer
2) IME (DesktopIMEHelper)
3) List .desktop entries (with filter)
4) Show required Arch packages
5) Exit
EOF
  read -rp "Select module: " choice
  case "$choice" in
    1) app_menu ;;
    2) ime_menu ;;
    3) list_desktops ;;
    4) show_arch_deps ;;
    5) exit 0 ;;
    *) echo "Invalid"; pause; main_menu ;;
  esac
}

app_menu() {
  clear_screen
  cat <<EOF
-------------------------
 AppImage Installer Menu
-------------------------
1) Install AppImage
2) Uninstall AppImage
3) Back
EOF
  read -rp "Select option: " opt
  case "$opt" in
    1)
      read -rp "Path to .AppImage: " path
      read -rp "Display name (optional): " name
      echo
      bash "$APP_INSTALL" "$path" "${name:-}"
      pause
      ;;
    2)
      bash "$APP_UNINSTALL"
      pause
      ;;
    3) main_menu ;;
    *) echo "Invalid"; pause ;;
  esac
  app_menu
}

ime_menu() {
  clear_screen
  cat <<EOF
-------------------------
 IME / Desktop Helper
-------------------------
1) Add fcitx5 IME to .desktop
2) Remove fcitx5 IME
3) Batch add to Electron/Qt
4) Add Wayland/Ozone flags
5) Remove Wayland/Ozone flags
6) Backup .desktop
7) Restore .desktop
8) Diagnose
9) Clean broken .desktop
10) Back
EOF
  read -rp "Select option: " opt
  case "$opt" in
    1) "$IMECTL" add-fcitx5 ;;
    2) "$IMECTL" remove-fcitx5 ;;
    3) "$IMECTL" batch-fcitx5 ;;
    4) "$IMECTL" add-wayland ;;
    5) "$IMECTL" remove-wayland ;;
    6) "$IMECTL" backup ;;
    7) "$IMECTL" restore ;;
    8) "$IMECTL" diagnose ;;
    9) "$IMECTL" clean-broken ;;
    10) main_menu ;;
    *) echo "Invalid";;
  esac
  pause
  ime_menu
}

show_arch_deps() {
  clear_screen
  cat <<'PKG'
Dependencies (Arch):

sudo pacman -S --needed \
bash coreutils grep sed awk findutils \
desktop-file-utils shared-mime-info \
imagemagick bsdtar fzf \
gtk-update-icon-cache plasma-workspace \
fuse2 fcitx5-im fcitx5-gtk fcitx5-qt
PKG
  echo
  pause
}

main_menu
