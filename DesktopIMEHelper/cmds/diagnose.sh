#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")"/.. && pwd)"
. "$DIR/lib/common.sh"

while IFS= read -r f; do
  [[ -z "$f" ]] && continue
  ex="$(get_exec "$f")"
  status=""
  grep -q 'fcitx5' <<<"$ex" && status+="IME "
  grep -qi 'ozone-platform' <<<"$ex" && status+="WAYLAND "
  # TryExec check
  te="$(awk -F= '/^TryExec=/{print $2; exit}' "$f")"
  if [[ -n "$te" && ! -x "$te" && ! -f "$te" ]]; then status+="BROKEN_TRYEXEC "; fi
  printf "%-12s %s\n" "[$status]" "$(basename -- "$f")"
done < <(_find_desktop_paths)
