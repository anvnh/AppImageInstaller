#!/usr/bin/env bash
set -euo pipefail

# Uninstall AppImages integrated by your installer.
# Detects .desktop with X-AppImage-Integrate=true or Exec/TryExec pointing to ~/Applications/*.appimage

# === Config (must match installer) ===
INSTALL_DIR="${HOME}/Applications"
DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
DESKTOP_DIR="${DATA_HOME}/applications"
ICON_BASE="${DATA_HOME}/icons/hicolor"

# Optional: set SYSTEM_WIDE=1 to also scan /usr/share (read-only unless run with sudo)
SYSTEM_WIDE="${SYSTEM_WIDE:-0}"

green() { printf "\033[1;32m[+]\033[0m %s\n" "$*"; }
yellow(){ printf "\033[1;33m[!]\033[0m %s\n" "$*"; }
red()   { printf "\033[1;31m[x]\033[0m %s\n" "$*"; }

shopt -s nocasematch

# --- helpers ---
strip_field_codes() {
  sed -E 's/(^|[[:space:]])%[fFuUdDnNickvm]//g' <<<"$1"
}

first_appimage_from_exec() {
  local exec_line="$1"
  exec_line="$(strip_field_codes "$exec_line")"

  # 1) quoted absolute path
  if [[ "$exec_line" =~ \"($HOME/Applications/[^\"\']+\.appimage)\" ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"; return 0
  fi
  # 2) unquoted absolute path
  if [[ "$exec_line" =~ ($HOME/Applications/[^\ \"\']+\.appimage) ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"; return 0
  fi
  # 3) sh -c "....AppImage ..."
  if [[ "$exec_line" =~ [\"\']?sh[\"\']?[[:space:]-c]*[[:space:]]*[\"\']([^\"\']*${HOME}/Applications/[^\"\']+\.appimage[^\"\']*)[\"\'] ]]; then
    local inside="${BASH_REMATCH[1]}"
    local cand
    cand="$(grep -oE "${HOME}/Applications/[^ \"']+\.appimage" <<<"$inside" | head -n1 || true)"
    [[ -n "$cand" ]] && { printf '%s\n' "$cand"; return 0; }
  fi
  # 4) env VAR=... env ... "AppImage"
  # tokenize by spaces preserving quotes
  local tokens=() t
  while read -r t; do tokens+=("$t"); done < <(awk 'BEGIN{RS=" "; ORS="\n"} {print}' <<<"$exec_line")
  local i=0
  while (( i < ${#tokens[@]} )); do
    [[ "${tokens[$i]}" == env ]] && ((i++)) && continue
    [[ "${tokens[$i]}" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]] && ((i++)) && continue
    break
  done
  if (( i < ${#tokens[@]} )); then
    local cmd="${tokens[$i]}"
    cmd="${cmd%\"}"; cmd="${cmd#\"}"; cmd="${cmd%\'}"; cmd="${cmd#\'}"
    if [[ "$cmd" =~ ^$HOME/Applications/.+\.appimage$ ]]; then
      printf '%s\n' "$cmd"; return 0
    fi
  fi
  return 1
}

resolve_path() {
  local p="$1"
  if command -v readlink >/dev/null 2>&1; then
    readlink -f -- "$p" 2>/dev/null || printf '%s' "$p"
  else
    printf '%s' "$p"
  fi
}

remove_icons_for_id() {
  local app_id="$1"
  local removed=false
  local roots=("$ICON_BASE")
  (( SYSTEM_WIDE == 1 )) && roots+=("/usr/share/icons/hicolor")

  for root in "${roots[@]}"; do
    [[ -d "$root" ]] || continue
    # png, svg, xpm at any size
    while IFS= read -r -d '' f; do
      rm -f -- "$f"; removed=true
    done < <(find "$root" -type f \( -name "${app_id}.png" -o -name "${app_id}.svg" -o -name "${app_id}.xpm" \) -print0 2>/dev/null || true)
  done
  $removed && green "Removed icons for: ${app_id}" || yellow "No icons for: ${app_id}"
}

refresh_caches() {
  command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "${DESKTOP_DIR}" || true
  command -v gtk-update-icon-cache >/dev/null 2>&1 && gtk-update-icon-cache -q "${ICON_BASE}" || true
  command -v kbuildsycoca6 >/dev/null 2>&1 && kbuildsycoca6 >/dev/null 2>&1 || command -v kbuildsycoca5 >/dev/null 2>&1 && kbuildsycoca5 >/dev/null 2>&1 || true
  command -v update-mime-database >/dev/null 2>&1 && update-mime-database "${DATA_HOME}/mime" || true
}

# --- discover .desktop files ---
declare -a SEARCH_DIRS=("$DESKTOP_DIR" "$DATA_HOME/flatpak/exports/share/applications")
(( SYSTEM_WIDE == 1 )) && SEARCH_DIRS+=("/usr/share/applications")

declare -a DESKTOP_FILES=()
for d in "${SEARCH_DIRS[@]}"; do
  [[ -d "$d" ]] || continue
  while IFS= read -r -d '' f; do DESKTOP_FILES+=("$f"); done < <(find "$d" -maxdepth 2 -type f -name '*.desktop' -print0 2>/dev/null || true)
done
[[ ${#DESKTOP_FILES[@]} -eq 0 ]] && { red "No .desktop entries found in scan roots."; exit 1; }

# Filter: our marker or Exec/TryExec pointing into INSTALL_DIR
declare -a CANDIDATES=()
for f in "${DESKTOP_FILES[@]}"; do
  [[ -f "$f" ]] || continue
  if grep -q '^X-AppImage-Integrate=true' "$f" 2>/dev/null; then
    CANDIDATES+=("$f"); continue
  fi
  if grep -q "^TryExec=${INSTALL_DIR}/.*\.appimage" "$f" 2>/dev/null; then
    CANDIDATES+=("$f"); continue
  fi
  if grep -q "^Exec=.*${INSTALL_DIR}/.*\.appimage" "$f" 2>/dev/null; then
    CANDIDATES+=("$f"); continue
  fi
done
[[ ${#CANDIDATES[@]} -eq 0 ]] && { red "No AppImage integrations detected."; exit 1; }

# --- build items ---
NAMES=()
APPS=()
ICONS=()
FILES=()

for dfile in "${CANDIDATES[@]}"; do
  name="$(grep -m1 '^Name=' "$dfile" | cut -d= -f2- || true)"
  tryexec="$(grep -m1 '^TryExec=' "$dfile" | cut -d= -f2- || true)"
  exec_line="$(grep -m1 '^Exec=' "$dfile" | cut -d= -f2- || true)"
  icon_val="$(grep -m1 '^Icon=' "$dfile" | cut -d= -f2- || true)"

  app_path=""
  if [[ -n "$tryexec" && "$tryexec" =~ \.appimage$ && -e "$tryexec" ]]; then
    app_path="$tryexec"
  elif [[ -n "$exec_line" ]]; then
    cand="$(first_appimage_from_exec "$exec_line" || true)"
    [[ -n "$cand" && -e "$cand" ]] && app_path="$cand"
  fi

  [[ -z "$app_path" ]] && continue

  app_path="$(resolve_path "$app_path")"
  [[ "$app_path" == "$INSTALL_DIR/"* ]] || continue

  # logical app_id for icons
  if [[ -n "$icon_val" && "$icon_val" != /* ]]; then
    app_id="$icon_val"
  else
    app_id="$(basename "$dfile" .desktop)"
  fi

  NAMES+=("${name:-$(basename "$app_path")}")
  APPS+=("$app_path")
  ICONS+=("$app_id::$icon_val")
  FILES+=("$dfile")
done

[[ ${#APPS[@]} -eq 0 ]] && { red "No uninstallable items under ${INSTALL_DIR}."; exit 1; }

# --- selection ---
declare -a IDX=()
if command -v fzf >/dev/null 2>&1; then
  MENU=()
  for i in "${!APPS[@]}"; do
    MENU+=("$i\t${NAMES[$i]}\t${APPS[$i]}")
  done
  sel="$(printf '%b\n' "${MENU[@]}" | fzf --multi --with-nth=2.. --prompt="Uninstall> " || true)"
  [[ -z "$sel" ]] && { yellow "Nothing selected."; exit 0; }
  while IFS=$'\t' read -r idx _; do IDX+=("$idx"); done <<< "$sel"
else
  echo "Select items to uninstall (space-separated indices). 'a' for all. 'q' to quit."
  for i in "${!APPS[@]}"; do
    printf "  [%d] %s\n      %s\n" "$i" "${NAMES[$i]}" "${APPS[$i]}"
  done
  printf "Choice: "
  read -r choice
  [[ "$choice" == [qQ] ]] && { yellow "Aborted."; exit 0; }
  if [[ "$choice" == [aA] ]]; then
    IDX=($(seq 0 $((${#APPS[@]}-1))))
  else
    read -r -a IDX <<<"$choice"
  fi
fi

# validate indices
declare -A seen=()
VALID=()
for idx in "${IDX[@]}"; do
  [[ "$idx" =~ ^[0-9]+$ ]] || continue
  (( idx < ${#APPS[@]} )) || continue
  [[ -n "${seen[$idx]:-}" ]] && continue
  seen[$idx]=1
  VALID+=("$idx")
done
[[ ${#VALID[@]} -eq 0 ]] && { yellow "Nothing valid selected."; exit 0; }

# --- uninstall ---
for i in "${VALID[@]}"; do
  app="${APPS[$i]}"
  dfile="${FILES[$i]}"
  name="${NAMES[$i]}"
  icon_info="${ICONS[$i]}"
  app_id="${icon_info%%::*}"
  raw_icon="${icon_info#*::}"

  echo "Removing: ${name}"
  if [[ -f "$app" || -L "$app" ]]; then
    rm -f -- "$app"
    green "Removed AppImage: $app"
  else
    yellow "AppImage missing: $app"
  fi

  if [[ -f "$dfile" ]]; then
    rm -f -- "$dfile"
    green "Removed desktop file: $dfile"
  else
    yellow "Desktop file missing: $dfile"
  fi

  remove_icons_for_id "$app_id"

  if [[ -n "$raw_icon" && "$raw_icon" == /* && -f "$raw_icon" ]]; then
    rm -f -- "$raw_icon"
    green "Removed explicit icon: $raw_icon"
  fi
done

refresh_caches
green "Done."
