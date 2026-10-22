#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

CHANNEL=${1:?stable or beta}
REF=${2:-HEAD}
LIMIT=15

[[ "$CHANNEL" == stable ]] && pattern='v*' || pattern='beta-*'
previous=$(git describe --tags --abbrev=0 --match "$pattern" "$REF^" 2>/dev/null || true)

changes=$(git log --no-merges --format='%s' "${previous:+$previous..}$REF" -- . ':(exclude)appcast.xml')
[[ -n "$changes" ]] || changes="Maintenance release"

count=$(printf '%s\n' "$changes" | wc -l | tr -d ' ')
printf '%s\n' "$changes" | head -n "$LIMIT" | sed 's/^/- /'
(( count > LIMIT )) && echo "- $((count - LIMIT)) more changes"
exit 0
