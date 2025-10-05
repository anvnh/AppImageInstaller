#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")"/.. && pwd)"
. "$DIR/lib/common.sh"

t="$(_resolve_target "${1:-}")"; [[ -n "$t" ]] || { echo "no target"; exit 1; }
dest="$(backup_user_copy "$t")"
echo "backup -> ${dest}.bak"
