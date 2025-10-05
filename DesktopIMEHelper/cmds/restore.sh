#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")"/.. && pwd)"
. "$DIR/lib/common.sh"

t="$(_resolve_target "${1:-}")"; [[ -n "$t" ]] || { echo "no target"; exit 1; }
dst="$t"; [[ "$t" == "$SYS_DESKTOP_DIR/"* ]] && dst="${USER_DESKTOP_DIR}/$(basename -- "$t")"
restore_from_bak "$dst"
refresh_caches
echo "restored: $dst"
