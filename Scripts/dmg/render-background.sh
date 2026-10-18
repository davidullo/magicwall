#!/usr/bin/env bash
#
# Regenerates the DMG window background from background.html.
#
#   ./Scripts/dmg/render-background.sh
#
# Outputs (committed):
#   Scripts/dmg/background.png      660 × 420 px, 72 dpi
#   Scripts/dmg/background@2x.png  1320 × 840 px, 144 dpi
#
# Requires Google Chrome, sips and the Inter/Geist Mono fonts already vendored
# in site/assets/font. The build itself only needs the committed PNGs.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
chrome="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"

die() { printf 'error: %s\n' "$*" >&2; exit 1; }

[[ -x "$chrome" ]] || die "Google Chrome not found at $chrome (set CHROME to override)"
[[ -f "$here/background.html" ]] || die "background.html not found"

work="$(mktemp -d "${TMPDIR:-/tmp}/magicwall-dmg-bg.XXXXXX")"
trap 'rm -rf "$work"' EXIT

render() {
    local scale="$1" out="$2" dpi="$3"
    local png="$work/background-${scale}x.png"

    # CSS pixels are always 660×420; the device scale factor only changes the
    # number of physical pixels in the screenshot.
    "$chrome" --headless=new --disable-gpu --hide-scrollbars \
        --force-device-scale-factor="$scale" --window-size=660,420 \
        --virtual-time-budget=3000 \
        --user-data-dir="$work/profile-$scale" \
        --screenshot="$png" "file://$here/background.html" >/dev/null 2>&1

    [[ -f "$png" ]] || die "Chrome did not produce $png"
    sips -s dpiWidth "$dpi" -s dpiHeight "$dpi" "$png" --out "$out" >/dev/null

    local w h
    w="$(sips -g pixelWidth "$out" | awk '/pixelWidth/ {print $2}')"
    h="$(sips -g pixelHeight "$out" | awk '/pixelHeight/ {print $2}')"
    [[ "$w" == "$((660 * scale))" && "$h" == "$((420 * scale))" ]] \
        || die "unexpected size for $out: ${w}×${h}"
    printf 'wrote %s (%s×%s, %s dpi)\n' "$out" "$w" "$h" "$dpi"
}

render 1 "$here/background.png" 72
render 2 "$here/background@2x.png" 144
