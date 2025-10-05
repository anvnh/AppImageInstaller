#!/usr/bin/env bash
set -euo pipefail

DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
USER_DESKTOP_DIR="${DATA_HOME}/applications"
SYS_DESKTOP_DIR="/usr/share/applications"
mkdir -p "${USER_DESKTOP_DIR}"

IME_ENV="GTK_IM_MODULE=fcitx5 QT_IM_MODULE=fcitx5 XMODIFIERS=@im=fcitx5 SDL_IM_MODULE=fcitx"
WAYLAND_FLAGS="--enable-features=UseOzonePlatform,WaylandWindowDecorations --ozone-platform=wayland --enable-wayland-ime"

need() { command -v "$1" >/dev/null 2>&1 || { echo "missing: $1"; exit 1; }; }

_find_desktop_paths() {
  find "$USER_DESKTOP_DIR" -maxdepth 1 -type f -name "*.desktop" -print
  find "$SYS_DESKTOP_DIR"  -maxdepth 1 -type f -name "*.desktop" -print 2>/dev/null || true
}

_resolve_target() {
  local key="${1:-}"
  if [[ -n "$key" ]]; then
    if [[ -f "$key" ]]; then echo "$key"; return; fi
    _find_desktop_paths | awk -v k="$key" '
      BEGIN{IGNORECASE=1}
      {b=$0; gsub(/^.*\//,"",b); gsub(/\.desktop$/,"",b);
       if ($0~k || b==k) print $0}' | head -n1
    return
  fi
  local list; list="$(_find_desktop_paths)"
  [[ -z "$list" ]] && { echo ""; return; }
  if command -v fzf >/dev/null 2>&1; then
    printf "%s\n" "$list" | fzf --prompt="Select .desktop > "
  else
    nl -ba <<<"$list"
    printf "Index: "; read -r i
    awk -v n="$i" 'NR==n{print; exit}' <<<"$list"
  fi
}

backup_user_copy() {
  local src="$1" base dest
  base="$(basename -- "$src")"
  if [[ "$src" == "$SYS_DESKTOP_DIR/"* ]]; then
    dest="${USER_DESKTOP_DIR}/${base}"
    cp -f -- "$src" "$dest"
  else
    dest="$src"
  fi
  [[ -f "$dest" ]] && cp -f -- "$dest" "${dest}.bak"
  echo "$dest"
}

restore_from_bak() {
  local f="$1"
  [[ -f "${f}.bak" ]] && cp -f -- "${f}.bak" "$f"
}

get_exec() { awk -F= '/^Exec=/{print substr($0,6); exit}' "$1"; }
set_exec() {
  local file="$1" new="$2"
  awk -v repl="$new" 'BEGIN{done=0}
    /^Exec=/ && !done {print "Exec="repl; done=1; next} {print}' "$file" > "${file}.tmp" && mv "${file}.tmp" "$file"
}

_strip_fields() { sed -E 's/(^|[[:space:]])%[fFuUdDnNickvm]//g' <<<"$1"; }
_fields_only() { grep -oE '%[fFuUdDnNickvm]' <<<"$1" | tr '\n' ' '; }

refresh_caches() {
  command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "${USER_DESKTOP_DIR}" || true
  command -v kbuildsycoca6 >/dev/null 2>&1 && kbuildsycoca6 >/dev/null 2>&1 || command -v kbuildsycoca5 >/dev/null 2>&1 && kbuildsycoca5 >/dev/null 2>&1 || true
}
