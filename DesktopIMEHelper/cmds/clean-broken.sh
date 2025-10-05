#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")"/.. && pwd)"
. "$DIR/lib/common.sh"

cnt=0
while IFS= read -r f; do
  te="$(awk -F= '/^TryExec=/{print $2; exit}' "$f")"
  if [[ -n "$te" && ! -f "$te" ]]; then
    rm -f -- "$f"; ((cnt++))
  fi
done < <(find "$USER_DESKTOP_DIR" -maxdepth 1 -name '*.desktop' -print)
refresh_caches
echo "removed: $cnt broken entries"
