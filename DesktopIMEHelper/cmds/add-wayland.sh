#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")"/.. && pwd)"
. "$DIR/lib/common.sh"

t="$(_resolve_target "${1:-}")"; [[ -n "$t" ]] || { echo "no target"; exit 1; }
dest="$(backup_user_copy "$t")"
execv="$(get_exec "$dest")"; fields="$(_fields_only "$execv")"; stripped="$(_strip_fields "$execv")"

grep -qi 'ozone-platform' <<<"$execv" && { echo "exists: $dest"; exit 0; }

new="${stripped} ${WAYLAND_FLAGS} ${fields}"
set_exec "$dest" "$(sed -E 's/[[:space:]]+/ /g' <<<"$new")"
refresh_caches
echo "added wayland: $dest"
