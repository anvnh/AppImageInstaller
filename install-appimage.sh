#!/usr/bin/env bash
set -euo pipefail

# === Defaults ===
INSTALL_DIR="${HOME}/Applications"
DESKTOP_DIR="${HOME}/.local/share/applications"
ICON_BASE="${HOME}/.local/share/icons/hicolor"

WAYLAND_IME=false
EXTRA_ARGS=""
FORCE_ICON=""

log()  { printf "\033[1;32m[+]\033[0m %s\n" "$*"; }
warn() { printf "\033[1;33m[!]\033[0m %s\n" "$*"; }
err()  { printf "\033[1;31m[x]\033[0m %s\n" "$*" >&2; }

usage() {
  cat <<EOF
Usage:
  $0 /path/to/AppName.AppImage [DisplayName] [options]

Options:
  --wayland-ime        Add Wayland IME env/flags for Electron apps
  --extra-args="..."   Append extra flags to Exec
  --force-icon=PATH    Force icon file (png/svg/xpm/webp/ico)

Examples:
  $0 ~/Downloads/Cursor.AppImage "Cursor" --wayland-ime
  $0 ~/Downloads/App.AppImage "My App" --force-icon=~/Pictures/app.png
EOF
  exit 1
}

sanitize_id() {
  local s
  s="$(tr '[:upper:]' '[:lower:]' <<<"$1" | tr -cs 'a-z0-9._-' '-')"
  s="${s%-}"; s="${s#-}"
  printf '%s\n' "$s"
}

expand_tilde() {
  local p="$1"
  [[ "$p" == "~" || "$p" == "~/"* ]] && printf '%s\n' "${p/#\~/$HOME}" || printf '%s\n' "$p"
}

ensure_icon_theme() {
  local index="${ICON_BASE}/index.theme"
  if [[ ! -f "${index}" ]]; then
    mkdir -p "${ICON_BASE}"
    cat > "${index}" <<'EOF'
[Icon Theme]
Name=hicolor
Comment=Default hicolor theme
Directories=16x16/apps,24x24/apps,32x32/apps,48x48/apps,64x64/apps,128x128/apps,256x256/apps,512x512/apps,scalable/apps
[16x16/apps]
Size=16
Context=Applications
Type=Fixed
[24x24/apps]
Size=24
Context=Applications
Type=Fixed
[32x32/apps]
Size=32
Context=Applications
Type=Fixed
[48x48/apps]
Size=48
Context=Applications
Type=Fixed
[64x64/apps]
Size=64
Context=Applications
Type=Fixed
[128x128/apps]
Size=128
Context=Applications
Type=Fixed
[256x256/apps]
Size=256
Context=Applications
Type=Fixed
[512x512/apps]
Size=512
Context=Applications
Type=Fixed
[scalable/apps]
Size=128
Type=Scalable
MinSize=8
MaxSize=512
Context=Applications
EOF
  fi
}

detect_icon_ext() {
  local f="$1" mime ext=""
  if command -v file >/dev/null 2>&1; then
    mime="$(file -b --mime-type "$f" 2>/dev/null || true)"
    case "$mime" in
      image/png) ext=png ;;
      image/svg+xml) ext=svg ;;
      image/x-xpixmap|image/xpm) ext=xpm ;;
      image/vnd.microsoft.icon|image/x-icon|image/ico) ext=ico ;;
      image/webp) ext=webp ;;
    esac
  fi
  [[ -n "$ext" ]] && { printf '%s\n' "$ext"; return; }
  head -c 8 "$f" | od -An -t x1 | tr -d ' \n' | grep -qi '^89504e470d0a1a0a$' && { echo png; return; }
  head -c 512 "$f" | tr -d '\000' | grep -qi '<svg' && { echo svg; return; }
  head -c 16 "$f" | tr -d '\000' | grep -qi 'XPM' && { echo xpm; return; }
  echo ""
}

# === Parse args ===
[[ $# -lt 1 ]] && usage
APPIMAGE_PATH="$1"; shift
[[ ! -f "${APPIMAGE_PATH}" ]] && { err "File not found: ${APPIMAGE_PATH}"; exit 1; }

DISPLAY_NAME=""
if [[ $# -gt 0 && "$1" != --* ]]; then DISPLAY_NAME="$1"; shift; fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --wayland-ime) WAYLAND_IME=true; shift ;;
    --extra-args=*) EXTRA_ARGS="${1#*=}"; shift ;;
    --force-icon=*) FORCE_ICON="$(expand_tilde "${1#*=}")"; shift ;;
    *) warn "Unknown option: $1"; shift ;;
  esac
done

BASENAME="$(basename -- "${APPIMAGE_PATH}")"
NAME_BASE="$(sed -E 's/\.(appimage|AppImage)$//I' <<<"${BASENAME}")"
APP_ID_RAW="$(sed -E 's/[-_]?([0-9]+(\.[0-9]+)*)[a-z0-9._-]*$//' <<<"${NAME_BASE}")"
[[ -z "${APP_ID_RAW}" ]] && APP_ID_RAW="${NAME_BASE}"
APP_ID="$(sanitize_id "${APP_ID_RAW}")"
[[ -z "${DISPLAY_NAME}" ]] && DISPLAY_NAME="$(tr '[:lower:]' '[:upper:]' <<<"${APP_ID:0:1}")${APP_ID:1}"

mkdir -p "${INSTALL_DIR}" "${DESKTOP_DIR}"

TARGET_APP="${INSTALL_DIR}/${BASENAME}"
install -Dm755 "/proc/self/fd/0" "${TARGET_APP}" < <(cat -- "${APPIMAGE_PATH}")
log "Installed: ${TARGET_APP}"

# === Extract resources (best-effort) ===
TMPDIR="$(mktemp -d)"
cleanup() { rm -rf "${TMPDIR}"; }
trap cleanup EXIT

SQUASH=""
if ( cd "${TMPDIR}" && "${TARGET_APP}" --appimage-extract >/dev/null 2>&1 ) \
  || ( cd "${TMPDIR}" && APPIMAGE="${TARGET_APP}" "${TARGET_APP}" --appimage-extract >/dev/null 2>&1 ); then
  SQUASH="${TMPDIR}/squashfs-root"
elif command -v bsdtar >/dev/null 2>&1; then
  # fallback for type2 AppImages that are simple squashfs
  if bsdtar -tf "${TARGET_APP}" >/dev/null 2>&1; then
    mkdir -p "${TMPDIR}/squashfs-root"
    (cd "${TMPDIR}/squashfs-root" && bsdtar -xf "${TARGET_APP}") || true
    [[ -d "${TMPDIR}/squashfs-root" ]] && SQUASH="${TMPDIR}/squashfs-root"
  fi
fi

[[ -z "${SQUASH}" || ! -d "${SQUASH}" ]] && warn "Could not extract resources."

# === Vendor desktop metadata ===
FOUND_DESKTOP=""
if [[ -n "${SQUASH}" ]]; then
  while IFS= read -r -d '' f; do FOUND_DESKTOP="$f"; break; done \
    < <(find "${SQUASH}" -maxdepth 3 -type f -name "*.desktop" -print0 2>/dev/null || true)
fi

VENDOR_NAME="${DISPLAY_NAME}"
VENDOR_COMMENT=""
STARTUP_WMCLASS=""
if [[ -n "${FOUND_DESKTOP}" ]]; then
  VENDOR_NAME="$(grep -m1 '^Name=' "${FOUND_DESKTOP}" | sed 's/^Name=//')" || true
  VENDOR_COMMENT="$(grep -m1 '^Comment=' "${FOUND_DESKTOP}" | sed 's/^Comment=//')" || true
  STARTUP_WMCLASS="$(grep -m1 '^StartupWMClass=' "${FOUND_DESKTOP}" | sed 's/^StartupWMClass=//')" || true
  [[ -z "${VENDOR_NAME}" ]] && VENDOR_NAME="${DISPLAY_NAME}"
fi

# === Icon install ===
ensure_icon_theme
ICON_NAME_SAFE="$(sanitize_id "${APP_ID}")"
ICON_INSTALLED_PATH=""
ICON_KEY="${ICON_NAME_SAFE}"

resolve_icon_path() { [[ -L "$1" ]] && readlink -f "$1" || printf '%s\n' "$1"; }

ICON_PATH_SRC=""
if [[ -n "${FORCE_ICON}" && -f "${FORCE_ICON}" ]]; then
  ICON_PATH_SRC="$(resolve_icon_path "${FORCE_ICON}")"
elif [[ -n "${SQUASH}" && -d "${SQUASH}" ]]; then
  mapfile -t CANDIDATES < <(
    find "${SQUASH}" -maxdepth 8 -type f \
      \( -iname "*.png" -o -iname "*.svg" -o -iname "*.xpm" -o -iname "*.webp" -o -iname "*.ico" -o -name ".DirIcon" \) \
      \( -path "*/usr/share/icons/*" -o -path "*/share/icons/*" -o -path "*/share/pixmaps/*" -o -path "*/icons/*" -o -path "${SQUASH}" \) \
      2>/dev/null
  )
  BEST=""
  BEST_SIZE=0
  for p in "${CANDIDATES[@]}"; do
    pp="$(resolve_icon_path "$p")"
    if [[ "$pp" =~ hicolor/([0-9]+)x\1/.* ]]; then
      sz="${BASH_REMATCH[1]}"
      (( sz > BEST_SIZE )) && { BEST_SIZE=$sz; BEST="$pp"; }
    fi
  done
  ICON_PATH_SRC="${BEST:-${CANDIDATES[0]:-}}"
fi

if [[ -n "${ICON_PATH_SRC}" && -e "${ICON_PATH_SRC}" ]]; then
  ext=""
  case "${ICON_PATH_SRC,,}" in
    *.png) ext=png ;; *.svg) ext=svg ;; *.xpm) ext=xpm ;; *.ico) ext=ico ;; *.webp) ext=webp ;;
    *) ext="$(detect_icon_ext "${ICON_PATH_SRC}")" ;;
  esac
  case "${ext}" in
    svg)
      install -Dm644 "${ICON_PATH_SRC}" "${ICON_BASE}/scalable/apps/${ICON_NAME_SAFE}.svg"
      ICON_INSTALLED_PATH="${ICON_BASE}/scalable/apps/${ICON_NAME_SAFE}.svg"
      ;;
    png|xpm)
      install -Dm644 "${ICON_PATH_SRC}" "${ICON_BASE}/512x512/apps/${ICON_NAME_SAFE}.png"
      ICON_INSTALLED_PATH="${ICON_BASE}/512x512/apps/${ICON_NAME_SAFE}.png"
      ;;
    ico|webp)
      if command -v convert >/dev/null 2>&1; then
        install -d "${ICON_BASE}/512x512/apps"
        convert "${ICON_PATH_SRC}" "${ICON_BASE}/512x512/apps/${ICON_NAME_SAFE}.png"
        ICON_INSTALLED_PATH="${ICON_BASE}/512x512/apps/${ICON_NAME_SAFE}.png"
      else
        warn "Icon is ${ext}; install imagemagick or use --force-icon=...png"
      fi
      ;;
    *) warn "Unknown icon type: ${ICON_PATH_SRC}" ;;
  esac
else
  warn "No icon found. Generic icon will be used."
fi

[[ -z "${ICON_INSTALLED_PATH}" ]] && ICON_KEY="${TARGET_APP}"

# === Build Exec line ===
IME_ENV=""
WAYLAND_FLAGS=""
if [[ "${WAYLAND_IME}" == true ]]; then
  IME_ENV="GTK_IM_MODULE=fcitx5 QT_IM_MODULE=fcitx5 XMODIFIERS=@im=fcitx5 SDL_IM_MODULE=fcitx5"
  WAYLAND_FLAGS="--enable-features=UseOzonePlatform,WaylandWindowDecorations --ozone-platform=wayland --enable-wayland-ime"
fi

# Escape any embedded double quotes in EXTRA_ARGS
EXTRA_ARGS_ESCAPED="${EXTRA_ARGS//\"/\\\"}"

FINAL_EXEC="env ${IME_ENV} \"${TARGET_APP}\" ${WAYLAND_FLAGS} ${EXTRA_ARGS_ESCAPED}"
FINAL_EXEC="$(sed -E 's/[[:space:]]+/ /g' <<<"${FINAL_EXEC}")"

# === Create .desktop ===
DESKTOP_FILE="${DESKTOP_DIR}/${APP_ID}.desktop"
cat > "${DESKTOP_FILE}" <<EOF
[Desktop Entry]
Type=Application
Name=${VENDOR_NAME}
Comment=${VENDOR_COMMENT}
Exec=${FINAL_EXEC} %F
TryExec=${TARGET_APP}
Icon=${ICON_KEY}
Terminal=false
Categories=Utility;
StartupNotify=true
X-AppImage-Integrate=true
EOF

[[ -n "${STARTUP_WMCLASS}" ]] && printf 'StartupWMClass=%s\n' "${STARTUP_WMCLASS}" >> "${DESKTOP_FILE}"

chmod 644 "${DESKTOP_FILE}"
log "Created desktop entry -> ${DESKTOP_FILE}"

# === Refresh caches ===
command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "${DESKTOP_DIR}" || true
command -v gtk-update-icon-cache >/dev/null 2>&1 && gtk-update-icon-cache -q "${ICON_BASE}" || true
command -v kbuildsycoca6 >/dev/null 2>&1 && kbuildsycoca6 || command -v kbuildsycoca5 >/dev/null 2>&1 && kbuildsycoca5 || true
command -v desktop-file-validate >/dev/null 2>&1 && desktop-file-validate "${DESKTOP_FILE}" || true

log "Done."
