#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")"/.. && pwd)"
. "$DIR/lib/common.sh"

t="$(_resolve_target "${1:-}")"; [[ -n "$t" ]] || { echo "no target"; exit 1; }
dest="$(backup_user_copy "$t")"
execv="$(get_exec "$dest")"; [[ -n "$execv" ]] || { echo "no Exec="; exit 1; }
fields="$(_fields_only "$execv")"
stripped="$(_strip_fields "$execv")"

read -r -a toks < <(awk 'BEGIN{RS=" "; ORS="\n"} {print}' <<<"$stripped")
i=0; out=(); seen_env=0
[[ "${toks[0]:-}" == env ]] && { seen_env=1; ((i++)); }
while (( i<${#toks[@]} )) && [[ "${toks[$i]}" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; do
  case "${toks[$i]}" in
    GTK_IM_MODULE=*|QT_IM_MODULE=*|XMODIFIERS=*|SDL_IM_MODULE=*) : ;;
    *) out+=("${toks[$i]}") ;;
  esac
  ((i++))
done
cmd=("${toks[@]:$i}")
if (( seen_env )); then
  new=$([[ ${#out[@]} -gt 0 ]] && echo "env ${out[*]} ${cmd[*]} ${fields}" || echo "${cmd[*]} ${fields}")
else
  new="$execv"
fi
set_exec "$dest" "$(sed -E 's/[[:space:]]+/ /g' <<<"$new")"
refresh_caches
echo "cleaned: $dest"
