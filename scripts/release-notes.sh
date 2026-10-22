#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

CHANNEL=${1:?stable or beta}
REF=${2:-HEAD}

[[ "$CHANNEL" == stable ]] && pattern='v*' || pattern='beta-*'
previous=$(git describe --tags --abbrev=0 --match "$pattern" "$REF^" 2>/dev/null || true)

changes=$(git log --format=%B "${previous:+$previous..}$REF" | sed -n 's/^Changelog: //p')
[[ -n "$changes" ]] || changes="Maintenance release"
printf '%s\n' "$changes" | sed 's/^/- /'
