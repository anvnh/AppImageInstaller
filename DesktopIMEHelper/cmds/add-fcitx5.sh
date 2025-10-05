#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd -- "$(dirname -- "${BASH_SCRIPT_SOURCE:-${BASH_SOURCE[0]}}")"/.. && pwd)"
# shellcheck source=../lib/common.sh
. "$DIR/lib/common.sh"

t="$(_resolve_target "${1:-}")"; [[ -n "$t" ]] || { echo "no target"; exit 1; }
dest="$(backup_user_copy "$t")"
execv="$(get_exec "$dest")"; [[ -n "$execv" ]] || { echo "no Exec="; exit 1; }
fields="$(_fields_only "$execv")"
stripped="$(_strip_fields "$execv")"

# Remove existing env vars
read -r -a toks < <(awk 'BEGIN{RS=" "; ORS="\n"} {print}' <<<"$stripped")
i=0; [[ "${toks[0]:-}" == env ]] && ((i++))
while (( i<${#toks[@]} )) && [[ "${toks[$i]}" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; do ((i++)); done
tail="${toks[*]:$i}"
new="env ${IME_ENV} ${tail} ${fields}"
set_exec "$dest" "$(sed -E 's/[[:space:]]+/ /g' <<<"$new")"
refresh_caches
echo "patched: $dest"
