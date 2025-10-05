#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")"/.. && pwd)"
. "$DIR/lib/common.sh"

list=$(
  { find "$USER_DESKTOP_DIR" -maxdepth 1 -name '*.desktop' -print; find "$SYS_DESKTOP_DIR" -maxdepth 1 -name '*.desktop' -print 2>/dev/null; } \
  | xargs grep -IlZ . 2>/dev/null \
  | xargs -0 grep -liE '(^Exec=.*(electron|code|cursor|chromium)|^Comment=.*(Electron|Qt))' 2>/dev/null || true
)
[[ -z "$list" ]] && { echo "no candidates"; exit 0; }

count=0
while IFS= read -r f; do
  [[ -z "$f" ]] && continue
  "$DIR/cmds/add-fcitx5.sh" "$f" >/dev/null || true
  ((count++)) || true
done <<< "$list"
echo "patched: $count file(s)"
