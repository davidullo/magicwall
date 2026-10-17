#!/usr/bin/env bash
# Renders the 1200×630 social card (assets/icon/og.jpg) from tools/og.html
# with headless Chrome. Usage: ./tools/og.sh
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
site="$(cd "$here/.." && pwd)"
out="$site/assets/icon"
poster="$site/assets/media/wallpaper-poster.jpg"
chrome="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
work="$(mktemp -d)"
tmp="$work/og.png"
trap 'rm -rf "$work"' EXIT

if [[ ! -x "$chrome" ]]; then
  echo "error: Google Chrome not found at $chrome" >&2
  exit 1
fi

if [[ ! -f "$poster" ]]; then
  echo "error: $poster is missing — it is the wallpaper still used by the card" >&2
  exit 1
fi

# --user-data-dir keeps headless Chrome out of the user's own profile.
"$chrome" --headless=new --disable-gpu --hide-scrollbars \
  --force-device-scale-factor=1 --window-size=1200,630 --virtual-time-budget=4000 \
  --user-data-dir="$work/profile" \
  --screenshot="$tmp" "file://$here/og.html" >/dev/null 2>&1

sips -s format jpeg -s formatOptions 82 "$tmp" --out "$out/og.jpg" >/dev/null

printf 'wrote %s (%s bytes)\n' "$out/og.jpg" "$(stat -f%z "$out/og.jpg")"
