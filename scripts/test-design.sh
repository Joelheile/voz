#!/bin/bash
# Layer 3: renders every screen and lists the images that changed since the baseline, so you only look at those.
# scripts/test-design.sh --update saves the current render as the baseline. Run it on main before you change the UI.
# It exits 0 either way: a change isn't a failure until you've looked at the image.
set -euo pipefail
cd "$(dirname "$0")/.."

BASELINE=build/design-baseline
CURRENT=build/design-current
swift build -q
rm -rf "$CURRENT"
.build/debug/Voz --render-design "$CURRENT" >/dev/null

if [[ "${1:-}" == "--update" ]]; then
    # Animated screens differ between renders of the same code, so two more renders find them and later runs skip them
    rm -rf "$BASELINE"
    mv "$CURRENT" "$BASELINE"
    : > "$BASELINE/unstable.txt"
    for _ in 1 2; do
        .build/debug/Voz --render-design "$CURRENT" >/dev/null
        for image in "$CURRENT"/*.png; do
            cmp -s "$image" "$BASELINE/$(basename "$image")" || basename "$image" >> "$BASELINE/unstable.txt"
        done
        rm -rf "$CURRENT"
    done
    sort -u -o "$BASELINE/unstable.txt" "$BASELINE/unstable.txt"
    echo "Saved $(ls "$BASELINE"/*.png | wc -l | tr -d ' ') images to $BASELINE, $(wc -l < "$BASELINE/unstable.txt" | tr -d ' ') animated ones are skipped"
    exit 0
fi
if [[ ! -d "$BASELINE" ]]; then
    echo "FAIL no baseline. Run scripts/test-design.sh --update on main first."
    exit 2
fi

changed=0
for image in "$CURRENT"/*.png; do
    name=$(basename "$image")
    grep -qxF "$name" "$BASELINE/unstable.txt" && continue
    if ! cmp -s "$image" "$BASELINE/$name"; then
        echo "$CURRENT/$name"
        changed=$((changed + 1))
    fi
done
for image in "$BASELINE"/*.png; do
    [[ -e "$CURRENT/$(basename "$image")" ]] || { echo "removed $(basename "$image")"; changed=$((changed + 1)); }
done
echo "Changed: $changed of $(ls "$CURRENT" | wc -l | tr -d ' '), skipped $(wc -l < "$BASELINE/unstable.txt" | tr -d ' ') animated"
