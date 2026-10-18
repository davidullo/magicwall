#!/usr/bin/env bash
#
# Builds the styled MagicWall installer DMG with dmgbuild.
#
#   ./Scripts/build-dmg.sh <path/to/MagicWall.app> <output.dmg> [version]
#
# Requires dmgbuild >= 1.6.7 (1.6.7 fixes Finder backgrounds on macOS 26.2+):
#
#   pipx install "dmgbuild>=1.6.7"
#
# The release script calls this after the app has been signed/notarized. It
# does not sign the DMG itself; release.sh does that afterwards.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

usage() {
    cat <<'EOF'
Usage: ./Scripts/build-dmg.sh <MagicWall.app> <output.dmg> [version]

Builds the branded installer window (background, 128 pt icons, Applications
drop target) with dmgbuild. Requires:

  pipx install "dmgbuild>=1.6.7"
EOF
}

die() { printf 'error: %s\n' "$*" >&2; exit 1; }

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
fi
if [[ $# -lt 2 ]]; then
    usage >&2
    exit 1
fi

APP="$1"
OUT="$2"
VERSION="${3:-}"

[[ -d "$APP" ]] || die "app bundle not found: $APP"
[[ -f "$ROOT/Scripts/dmg/background.png" ]] || die "missing Scripts/dmg/background.png"
[[ -f "$ROOT/Scripts/dmg/background@2x.png" ]] || die "missing Scripts/dmg/background@2x.png"
[[ -f "$ROOT/Scripts/dmg-settings.py" ]] || die "missing Scripts/dmg-settings.py"

APP_NAME="${APP_NAME:-$(basename "$APP" .app)}"
[[ "$OUT" == *.dmg ]] || die "output must end in .dmg: $OUT"
mkdir -p "$(dirname "$OUT")"

find_dmgbuild() {
    if [[ -n "${DMGBUILD:-}" ]]; then
        printf '%s\n' "$DMGBUILD"
        return 0
    fi
    if command -v dmgbuild >/dev/null 2>&1; then
        command -v dmgbuild
        return 0
    fi
    for candidate in \
        "$HOME/.local/bin/dmgbuild" \
        "/opt/homebrew/bin/dmgbuild" \
        "/usr/local/bin/dmgbuild"
    do
        [[ -x "$candidate" ]] && { printf '%s\n' "$candidate"; return 0; }
    done
    return 1
}

DMGBUILD_BIN="$(find_dmgbuild || true)"
if [[ -z "$DMGBUILD_BIN" ]]; then
    cat >&2 <<'EOF'
error: dmgbuild not found.

Install it with:
  pipx install "dmgbuild>=1.6.7"

(or set DMGBUILD=/path/to/dmgbuild).
EOF
    exit 1
fi

# Best-effort version check. dmgbuild has no --version flag; when it is the
# pipx console script, its shebang points at the venv Python that can report
# the installed distribution metadata.
DMGBUILD_VERSION=""
DMGBUILD_PY="$(sed -n '1s/^#!//p' "$DMGBUILD_BIN" 2>/dev/null || true)"
if [[ -n "$DMGBUILD_PY" && -x "$DMGBUILD_PY" ]]; then
    DMGBUILD_VERSION="$("$DMGBUILD_PY" -c \
        'import importlib.metadata; print(importlib.metadata.version("dmgbuild"))' \
        2>/dev/null || true)"
fi
if [[ -n "$DMGBUILD_VERSION" ]]; then
    oldest="$(printf '%s\n%s\n' "1.6.7" "$DMGBUILD_VERSION" | sort -V | head -1)"
    if [[ "$oldest" != "1.6.7" ]]; then
        cat >&2 <<EOF
error: dmgbuild $DMGBUILD_VERSION is too old (need >= 1.6.7).

Upgrade it with:
  pipx upgrade dmgbuild
EOF
        exit 1
    fi
else
    echo "warning: could not determine dmgbuild version; 1.6.7 or later is required" >&2
fi

echo "▸ DMG layout"
echo "  app:      $APP_NAME$([[ -n "$VERSION" ]] && echo " $VERSION")"
echo "  window:   660×448 pt (660×420 pt content)"
echo "  icons:    128 pt @ (180,200) + (480,200)"
echo "  tool:     $DMGBUILD_BIN${DMGBUILD_VERSION:+ ($DMGBUILD_VERSION)}"

rm -f "$OUT"

# The background pair (background.png + background@2x.png) is detected by
# dmgbuild and compiled into a multi-resolution TIFF automatically.
VOLUME_NAME="$APP_NAME"
[[ -n "$VERSION" ]] && VOLUME_NAME+=" $VERSION"

"$DMGBUILD_BIN" -s "$ROOT/Scripts/dmg-settings.py" \
    -D app="$APP" \
    -D app_name="$APP_NAME" \
    -D version="$VERSION" \
    -D background="$ROOT/Scripts/dmg/background.png" \
    "$VOLUME_NAME" "$OUT"

[[ -f "$OUT" ]] || die "dmgbuild did not create $OUT"
printf 'wrote %s (%s)\n' "$OUT" "$(du -h "$OUT" | awk '{print $1}')"
