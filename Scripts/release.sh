#!/usr/bin/env bash
#
# Builds a distributable MagicWall release.
#
#   ./Scripts/release.sh                    # universal build, ad-hoc signed
#   ./Scripts/release.sh --native           # fast build for this Mac only
#   ./Scripts/release.sh --publish          # also create the GitHub release
#
# Developer ID + notarization (requires an Apple Developer account):
#
#   SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
#   NOTARY_PROFILE=magicwall \
#   ./Scripts/release.sh --notarize
#
# Output (dist/):
#   MagicWall-<version>.dmg
#   MagicWall-<version>.zip
#   MagicWall-<version>.dSYM.zip   (when available)
#   SHA256SUMS.txt
#
# The version comes from project.yml (MARKETING_VERSION/CURRENT_PROJECT_VERSION)
# and can be overridden with --version / --build.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

APP_NAME="MagicWall"
DIST="$ROOT/dist"
BUILD_DIR="$ROOT/build/release"
UNIVERSAL=1
PUBLISH=0
NOTARIZE=0

VERSION="$(sed -n 's/^[[:space:]]*MARKETING_VERSION: "\(.*\)"$/\1/p' project.yml | head -1)"
BUILD_NUMBER="$(sed -n 's/^[[:space:]]*CURRENT_PROJECT_VERSION: "\(.*\)"$/\1/p' project.yml | head -1)"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"

usage() {
    cat <<'EOF'
Builds a distributable MagicWall release.

  ./Scripts/release.sh                    # universal build, ad-hoc signed
  ./Scripts/release.sh --native           # fast build for this Mac only
  ./Scripts/release.sh --publish          # also create the GitHub release

Developer ID + notarization (requires an Apple Developer account):

  SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
  NOTARY_PROFILE=magicwall \
  ./Scripts/release.sh --notarize

Output: dist/MagicWall-<version>.dmg, .zip, SHA256SUMS.txt (+ .dSYM.zip).
EOF
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --version) VERSION="$2"; shift 2 ;;
        --build) BUILD_NUMBER="$2"; shift 2 ;;
        --native) UNIVERSAL=0; shift ;;
        --publish) PUBLISH=1; shift ;;
        --notarize) NOTARIZE=1; shift ;;
        -h|--help) usage ;;
        *) echo "Unknown option: $1" >&2; usage ;;
    esac
done

if [[ -z "$VERSION" || -z "$BUILD_NUMBER" ]]; then
    echo "Could not read MARKETING_VERSION/CURRENT_PROJECT_VERSION from project.yml" >&2
    exit 1
fi

if [[ "$NOTARIZE" -eq 1 ]]; then
    if [[ "$SIGN_IDENTITY" == "-" ]]; then
        echo "--notarize requires SIGN_IDENTITY (Developer ID Application)." >&2
        exit 1
    fi
    if [[ -z "$NOTARY_PROFILE" ]]; then
        echo "--notarize requires NOTARY_PROFILE (a notarytool keychain profile)." >&2
        exit 1
    fi
fi

if [[ "$PUBLISH" -eq 1 ]] && ! command -v gh >/dev/null; then
    echo "--publish requires the GitHub CLI (gh)." >&2
    exit 1
fi

echo "▸ MagicWall $VERSION ($BUILD_NUMBER)"
echo "  identity: $SIGN_IDENTITY"
echo "  archs:    $([[ "$UNIVERSAL" -eq 1 ]] && echo 'arm64 x86_64' || echo 'native')"

# Serialize project generation with the other tooling (agents, Xcode, e2e).
LOCK=/tmp/mw-xcodegen.lock
while ! mkdir "$LOCK" 2>/dev/null; do sleep 1; done
trap 'rmdir "$LOCK" 2>/dev/null || true' EXIT
xcodegen generate >/dev/null
rmdir "$LOCK"
trap - EXIT

if [[ "$UNIVERSAL" -eq 1 ]]; then
    ARCHS_VALUE="arm64 x86_64"
else
    ARCHS_VALUE="$(uname -m)"
fi
ARCH_ARGS=(ONLY_ACTIVE_ARCH=NO ARCHS="$ARCHS_VALUE")

echo "▸ Building Release…"
xcodebuild \
    -project MagicWall.xcodeproj \
    -scheme MagicWall \
    -configuration Release \
    -derivedDataPath "$BUILD_DIR" \
    -quiet \
    MARKETING_VERSION="$VERSION" \
    CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
    ${ARCH_ARGS[@]+"${ARCH_ARGS[@]}"} \
    build

APP="$BUILD_DIR/Build/Products/Release/$APP_NAME.app"
if [[ ! -d "$APP" ]]; then
    echo "Build succeeded but $APP is missing." >&2
    exit 1
fi

BUILT_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
if [[ "$BUILT_VERSION" != "$VERSION" ]]; then
    echo "Version mismatch: built $BUILT_VERSION, expected $VERSION." >&2
    exit 1
fi

echo "▸ Signing…"
codesign --force --options runtime --sign "$SIGN_IDENTITY" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

rm -rf "$DIST"
mkdir -p "$DIST"

ZIP="$DIST/$APP_NAME-$VERSION.zip"
DMG="$DIST/$APP_NAME-$VERSION.dmg"
DSYM="$DIST/$APP_NAME-$VERSION.dSYM.zip"
DSYM_SRC="$BUILD_DIR/Build/Products/Release/$APP_NAME.app.dSYM"

# Notarize the app payload first, then staple the ticket so first launch also
# works offline. The DMG/zip below are built from the stapled app.
if [[ "$NOTARIZE" -eq 1 ]]; then
    echo "▸ Notarizing (this can take a few minutes)…"
    ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
    xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$APP"
    rm -f "$ZIP"
fi

echo "▸ Packaging…"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

STAGE="$(mktemp -d "${TMPDIR:-/tmp}/magicwall-dmg.XXXXXX")"
ditto "$APP" "$STAGE/$APP_NAME.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -quiet -volname "$APP_NAME $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
rm -rf "$STAGE"

if [[ "$SIGN_IDENTITY" != "-" ]]; then
    codesign --force --sign "$SIGN_IDENTITY" "$DMG"
    codesign --verify --verbose=2 "$DMG"
fi

if [[ -d "$DSYM_SRC" ]]; then
    ditto -c -k --sequesterRsrc --keepParent "$DSYM_SRC" "$DSYM"
fi

(
    cd "$DIST"
    shasum -a 256 "$APP_NAME-$VERSION.dmg" "$APP_NAME-$VERSION.zip" > SHA256SUMS.txt
    if [[ -f "$DSYM" ]]; then
        shasum -a 256 "$APP_NAME-$VERSION.dSYM.zip" >> SHA256SUMS.txt
    fi
)

echo
echo "✓ Artifacts in dist/:"
ls -lh "$DIST"
echo

if [[ "$SIGN_IDENTITY" == "-" ]]; then
    cat <<'EOF'
⚠ Ad-hoc signature: the app runs on this Mac, but other Macs will show
  "MagicWall is damaged / cannot be opened" because it is not notarized.
  Users can bypass it with:  xattr -dr com.apple.quarantine /Applications/MagicWall.app
  For a frictionless download, build with SIGN_IDENTITY + --notarize.
EOF
fi

if [[ "$PUBLISH" -eq 1 ]]; then
    echo "▸ Publishing GitHub release v$VERSION…"
    FILES=("$DMG" "$ZIP" "$DIST/SHA256SUMS.txt")
    if [[ -f "$DSYM" ]]; then
        FILES+=("$DSYM")
    fi
    gh release create "v$VERSION" \
        --title "$APP_NAME $VERSION" \
        --generate-notes \
        "${FILES[@]}"
fi
