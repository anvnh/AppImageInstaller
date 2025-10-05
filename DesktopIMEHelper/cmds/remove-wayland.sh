#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")"/.. && pwd)"
. "$DIR/lib/common.sh"

t="$(_resolve_target "${1:-}")"; [[ -n "$t" ]] || { echo "no target"; exit 1; }
dest="$(backup_user_copy "$t")"
execv="$(get_exec "$dest")"
execv="$(sed -E 's/--enable-features=UseOzonePlatform,WaylandWindowDecorations//g;s/--ozone-platform=wayland//g;s/--enable-wayland-ime//g' <<<"$execv")"
set_exec "$dest" "$(sed -E 's/[[:space:]]+/ /g' <<<"$execv")"
refresh_caches
echo "removed wayland: $dest"
