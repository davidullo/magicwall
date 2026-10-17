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
# Developer ID builds also produce the Sparkle appcast (dist/appcast.xml),
# which is attached to the GitHub release and read by installed apps via
#   https://github.com/davidullo/magicwall/releases/latest/download/appcast.xml
#
# Output (dist/):
#   MagicWall-<version>.dmg
#   MagicWall-<version>.zip
#   MagicWall-<version>.dSYM.zip   (when available)
#   appcast.xml                    (Developer ID builds only)
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
DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"

# The team is needed so xcodebuild signs Sparkle's nested helpers with the
# same identity; derive it from "Name (TEAMID)" when not passed explicitly.
if [[ "$SIGN_IDENTITY" != "-" && -z "$DEVELOPMENT_TEAM" ]]; then
    DEVELOPMENT_TEAM="$(sed -n 's/.*(\([A-Z0-9]\{10\}\))$/\1/p' <<<"$SIGN_IDENTITY" | head -1)"
fi

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

Developer ID builds also generate dist/appcast.xml for Sparkle auto-updates
(EdDSA key from the login keychain; SPARKLE_ED_KEY_FILE to use a key file).
--publish attaches it to the GitHub release, which serves the feed at
https://github.com/davidullo/magicwall/releases/latest/download/appcast.xml

Output: dist/MagicWall-<version>.dmg, .zip, SHA256SUMS.txt (+ .dSYM.zip,
appcast.xml on Developer ID builds).
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

# Sparkle embeds XPC services and helper executables inside the app; they must
# all carry the same Developer ID signature as the app, otherwise update
# installation and notarization fail. Passing the identity to xcodebuild signs
# every nested component; the codesign calls below re-assert the outer app.
SIGN_ARGS=()
if [[ "$SIGN_IDENTITY" != "-" ]]; then
    SIGN_ARGS=(CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$SIGN_IDENTITY")
    if [[ -n "$DEVELOPMENT_TEAM" ]]; then
        SIGN_ARGS+=(DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM")
    fi
fi

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
    ${SIGN_ARGS[@]+"${SIGN_ARGS[@]}"} \
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

# Sparkle's binary distribution ships its helpers ad-hoc signed. Xcode
# re-signs the framework and the app, but NOT the code nested inside the
# framework (XPC services, Updater.app, Autoupdate): notarization would reject
# them and the Installer could not run. Re-sign them first, from the innermost
# code outwards, then the framework, then the app (never use --deep on the
# whole app: it is deprecated and hides exactly this kind of problem).
SPARKLE_FW="$APP/Contents/Frameworks/Sparkle.framework"
if [[ "$SIGN_IDENTITY" != "-" && -d "$SPARKLE_FW" ]]; then
    SPARKLE_B="$SPARKLE_FW/Versions/Current"

    for component in \
        "$SPARKLE_B/XPCServices/Installer.xpc" \
        "$SPARKLE_B/XPCServices/Downloader.xpc" \
        "$SPARKLE_B/Autoupdate" \
        "$SPARKLE_B/Updater.app"
    do
        [[ -e "$component" ]] || continue
        if [[ "$component" == *Downloader.xpc ]]; then
            # Sparkle >= 2.6: the Downloader keeps its own entitlements.
            codesign --force --options runtime --timestamp \
                --preserve-metadata=entitlements \
                --sign "$SIGN_IDENTITY" "$component"
        else
            codesign --force --options runtime --timestamp \
                --sign "$SIGN_IDENTITY" "$component"
        fi
    done

    codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$SPARKLE_FW"
fi

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

# Sparkle appcast. Installed apps read it from
#   https://github.com/davidullo/magicwall/releases/latest/download/appcast.xml
# so it must be attached to every release. Only Developer ID builds can
# install updates, so the feed is only produced for those. The archives
# directory is persistent (build/ is gitignored): generate_appcast keeps one
# item per version with the right download URL and signature.
APPCAST=""
if [[ "$SIGN_IDENTITY" != "-" ]]; then
    SPARKLE_BIN="${SPARKLE_BIN:-}"
    if [[ -z "$SPARKLE_BIN" ]]; then
        for candidate in \
            "$BUILD_DIR/SourcePackages/artifacts/sparkle/Sparkle/bin" \
            "$HOME/Library/Developer/Xcode/DerivedData/"*/SourcePackages/artifacts/sparkle/Sparkle/bin
        do
            if [[ -x "$candidate/generate_appcast" ]]; then
                SPARKLE_BIN="$candidate"
                break
            fi
        done
    fi

    if [[ -x "${SPARKLE_BIN:-}/generate_appcast" ]]; then
        UPDATES_DIR="$ROOT/build/updates"
        mkdir -p "$UPDATES_DIR"
        cp "$ZIP" "$UPDATES_DIR/"

        echo "▸ Generating Sparkle appcast…"
        # Deltas are disabled on purpose: the app is ~7 MB and delta files
        # would also have to be uploaded next to the ZIP. The EdDSA private
        # key is normally read from the login keychain (Sparkle's
        # generate_keys); CI can pass a key file via SPARKLE_ED_KEY_FILE.
        APPCAST_ARGS=(
            --download-url-prefix "https://github.com/davidullo/magicwall/releases/download/v$VERSION/"
            --link "https://magicwall.davide.fyi"
            --full-release-notes-url "https://github.com/davidullo/magicwall/releases/tag/v$VERSION"
            --maximum-deltas 0
        )
        if [[ -n "${SPARKLE_ED_KEY_FILE:-}" ]]; then
            APPCAST_ARGS+=(--ed-key-file "$SPARKLE_ED_KEY_FILE")
        fi

        "$SPARKLE_BIN/generate_appcast" "${APPCAST_ARGS[@]}" "$UPDATES_DIR"
        cp "$UPDATES_DIR/appcast.xml" "$DIST/appcast.xml"
        APPCAST="$DIST/appcast.xml"
    else
        echo "⚠ Sparkle tools not found (set SPARKLE_BIN to the folder with" >&2
        echo "  generate_appcast, usually .../SourcePackages/artifacts/sparkle/Sparkle/bin):" >&2
        echo "  appcast.xml was not generated." >&2
    fi
else
    echo "ℹ Ad-hoc signature: appcast.xml not generated (Sparkle updates require a Developer ID build)."
fi

echo
echo "✓ Artifacts in dist/:"
ls -lh "$DIST"
echo

if [[ -n "$APPCAST" ]]; then
    echo "  Feed URL: https://github.com/davidullo/magicwall/releases/latest/download/appcast.xml"
    echo
fi

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
    if [[ -z "$APPCAST" ]]; then
        echo "Refusing to publish: the Sparkle appcast is missing, installed" >&2
        echo "apps would lose the update feed. Build with a Developer ID." >&2
        exit 1
    fi

    FILES=("$DMG" "$ZIP" "$DIST/SHA256SUMS.txt" "$APPCAST")
    if [[ -f "$DSYM" ]]; then
        FILES+=("$DSYM")
    fi
    gh release create "v$VERSION" \
        --title "$APP_NAME $VERSION" \
        --generate-notes \
        "${FILES[@]}"
fi
