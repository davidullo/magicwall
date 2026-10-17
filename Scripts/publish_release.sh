#!/usr/bin/env bash
#
# One-command release for MagicWall.
#
#   ./Scripts/publish_release.sh 0.2.0
#   ./Scripts/publish_release.sh 0.2.0 --build 3 --yes
#   ./Scripts/publish_release.sh 0.3.0 --no-publish   # build + appcast only
#
# What it does, in order:
#   1. validates the version and the environment (Developer ID, notary profile,
#      gh auth) and shows everything that is about to be committed;
#   2. bumps MARKETING_VERSION / CURRENT_PROJECT_VERSION in project.yml;
#   3. runs the MagicWallCore tests;
#   4. commits all pending changes as "Release v<version>" and pushes;
#   5. calls Scripts/release.sh --notarize [--publish] (build, Developer ID
#      signing incl. Sparkle helpers, notarization, DMG/ZIP/dSYM, appcast);
#   6. verifies the published feed (appcast.xml with the new build number and
#      the EdDSA signature) and the release assets.
#
# Required environment:
#   SIGN_IDENTITY="Developer ID Application: Name (TEAMID)"
#   NOTARY_PROFILE=magicwall
#
# Options:
#   --build N        explicit build number (default: current + 1)
#   --yes            do not ask for confirmation
#   --skip-tests     skip the core test suite
#   --with-e2e       also run the XCUITest suite before building
#   --no-publish     build, sign, notarize and generate the appcast, but do
#                    not create the GitHub release (nothing is pushed either
#                    unless it is a normal build run)
#   --no-push        commit locally but do not push
#   --no-commit      do not touch git at all
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

VERSION=""
BUILD_NUMBER=""
ASSUME_YES=0
RUN_TESTS=1
RUN_E2E=0
PUBLISH=1
PUSH=1
COMMIT=1

usage() {
    sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --build) BUILD_NUMBER="$2"; shift 2 ;;
        --yes|-y) ASSUME_YES=1; shift ;;
        --skip-tests) RUN_TESTS=0; shift ;;
        --with-e2e) RUN_E2E=1; shift ;;
        --no-publish) PUBLISH=0; shift ;;
        --no-push) PUSH=0; shift ;;
        --no-commit) COMMIT=0; shift ;;
        -h|--help) usage ;;
        -*) echo "Unknown option: $1" >&2; usage ;;
        *)
            if [[ -n "$VERSION" ]]; then
                echo "Only one version argument is allowed." >&2
                exit 1
            fi
            VERSION="$1"; shift ;;
    esac
done

if [[ -z "$VERSION" ]]; then
    echo "Usage: $0 <version> [--build N] [--yes] [--skip-tests] [--with-e2e]" >&2
    echo "       [--no-publish] [--no-push] [--no-commit]" >&2
    exit 1
fi

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Version must look like 0.2.0 (got: $VERSION)." >&2
    exit 1
fi

CURRENT_VERSION="$(sed -n 's/^[[:space:]]*MARKETING_VERSION: "\(.*\)"$/\1/p' project.yml | head -1)"
CURRENT_BUILD="$(sed -n 's/^[[:space:]]*CURRENT_PROJECT_VERSION: "\(.*\)"$/\1/p' project.yml | head -1)"

if [[ -z "$CURRENT_VERSION" || -z "$CURRENT_BUILD" ]]; then
    echo "Could not read the current version from project.yml." >&2
    exit 1
fi

if [[ "$VERSION" == "$CURRENT_VERSION" ]]; then
    echo "project.yml is already at $VERSION: pass the next version." >&2
    exit 1
fi

if [[ -z "$BUILD_NUMBER" ]]; then
    BUILD_NUMBER="$((CURRENT_BUILD + 1))"
fi

if [[ ! "$BUILD_NUMBER" =~ ^[0-9]+$ ]]; then
    echo "Build number must be an integer (got: $BUILD_NUMBER)." >&2
    exit 1
fi

if (( BUILD_NUMBER <= CURRENT_BUILD )); then
    echo "Build number must grow: current is $CURRENT_BUILD, got $BUILD_NUMBER." >&2
    exit 1
fi

if [[ "$PUBLISH" -eq 1 ]]; then
    for tool in gh curl; do
        command -v "$tool" >/dev/null || { echo "$tool is required." >&2; exit 1; }
    done
    if ! gh auth status >/dev/null 2>&1; then
        echo "gh is not authenticated (run: gh auth login)." >&2
        exit 1
    fi
    if gh release view "v$VERSION" >/dev/null 2>&1; then
        echo "Release v$VERSION already exists on GitHub." >&2
        exit 1
    fi
fi

if [[ -z "${SIGN_IDENTITY:-}" || "${SIGN_IDENTITY}" == "-" ]]; then
    echo 'SIGN_IDENTITY is required, e.g. SIGN_IDENTITY="Developer ID Application: Name (TEAMID)".' >&2
    exit 1
fi

if [[ -z "${NOTARY_PROFILE:-}" ]]; then
    echo "NOTARY_PROFILE is required (a notarytool keychain profile)." >&2
    exit 1
fi

# ---------------------------------------------------------------- dirty tree

DIRTY=0
if ! git diff --quiet || ! git diff --cached --quiet || [[ -n "$(git ls-files --others --exclude-standard)" ]]; then
    DIRTY=1
fi

echo
echo "▸ MagicWall release"
echo "  version:   $CURRENT_VERSION ($CURRENT_BUILD) → $VERSION ($BUILD_NUMBER)"
echo "  identity:  $SIGN_IDENTITY"
echo "  notary:    $NOTARY_PROFILE"
echo "  publish:   $([[ "$PUBLISH" -eq 1 ]] && echo 'GitHub release + appcast' || echo 'no (--no-publish)')"
echo "  tests:     $([[ "$RUN_TESTS" -eq 1 ]] && echo 'core' || echo 'skipped')$([[ "$RUN_E2E" -eq 1 ]] && echo ' + E2E')"
echo "  git:       $([[ "$COMMIT" -eq 1 ]] && echo 'commit all changes' || echo 'no commit')$([[ "$PUSH" -eq 1 && "$COMMIT" -eq 1 ]] && echo ' + push' || true)"
echo

if [[ "$DIRTY" -eq 1 ]]; then
    echo "  Uncommitted changes that will go into the release commit:"
    git status --short | sed 's/^/    /'
    echo
fi

if [[ "$ASSUME_YES" -ne 1 ]]; then
    read -r -p "Proceed? [y/N] " answer
    [[ "$answer" == "y" || "$answer" == "Y" ]] || { echo "Aborted."; exit 1; }
fi

# ------------------------------------------------------------------- bump

echo "▸ Bumping project.yml…"
sed -i '' -E "s/^([[:space:]]*MARKETING_VERSION: \").*(\")$/\1$VERSION\2/" project.yml
sed -i '' -E "s/^([[:space:]]*CURRENT_PROJECT_VERSION: \").*(\")$/\1$BUILD_NUMBER\2/" project.yml

NEW_VERSION="$(sed -n 's/^[[:space:]]*MARKETING_VERSION: "\(.*\)"$/\1/p' project.yml | head -1)"
NEW_BUILD="$(sed -n 's/^[[:space:]]*CURRENT_PROJECT_VERSION: "\(.*\)"$/\1/p' project.yml | head -1)"
if [[ "$NEW_VERSION" != "$VERSION" || "$NEW_BUILD" != "$BUILD_NUMBER" ]]; then
    echo "Failed to bump project.yml (got $NEW_VERSION/$NEW_BUILD)." >&2
    exit 1
fi

# ------------------------------------------------------------------- tests

if [[ "$RUN_TESTS" -eq 1 ]]; then
    echo "▸ Running core tests…"
    (cd Packages/MagicWallCore && swift test -q)
fi

if [[ "$RUN_E2E" -eq 1 ]]; then
    echo "▸ Running E2E tests…"
    ./Scripts/e2e.sh
fi

# ------------------------------------------------------------------- commit

if [[ "$COMMIT" -eq 1 ]]; then
    echo "▸ Committing…"
    git add -A
    git commit -q -m "Release v$VERSION"
    if [[ "$PUSH" -eq 1 ]]; then
        echo "▸ Pushing to $(git remote get-url origin)…"
        git push origin HEAD
    fi
fi

# ------------------------------------------------------------------ release

RELEASE_ARGS=(--notarize)
if [[ "$PUBLISH" -eq 1 ]]; then
    RELEASE_ARGS+=(--publish)
fi

echo "▸ Building, signing, notarizing and packaging (this takes a while)…"
SIGN_IDENTITY="$SIGN_IDENTITY" NOTARY_PROFILE="$NOTARY_PROFILE" \
    ./Scripts/release.sh "${RELEASE_ARGS[@]}"

# ------------------------------------------------------------------- verify

if [[ "$PUBLISH" -eq 1 ]]; then
    FEED_URL="https://github.com/davidullo/magicwall/releases/latest/download/appcast.xml"
    echo "▸ Verifying the published feed…"

    OK=0
    for attempt in {1..10}; do
        if curl -fsSL "$FEED_URL" -o /tmp/magicwall-appcast.xml 2>/dev/null \
            && grep -q "<sparkle:version>$BUILD_NUMBER</sparkle:version>" /tmp/magicwall-appcast.xml \
            && grep -q "edSignature" /tmp/magicwall-appcast.xml
        then
            OK=1
            break
        fi
        sleep 3
    done

    if [[ "$OK" -ne 1 ]]; then
        echo "⚠ The feed does not expose v$BUILD_NUMBER yet. Check the release assets:" >&2
        echo "  gh release view v$VERSION" >&2
        exit 1
    fi

    echo "  feed OK: appcast.xml exposes build $BUILD_NUMBER with a signature"
    echo

    cat <<EOF
✓ Release v$VERSION published.

  https://github.com/davidullo/magicwall/releases/tag/v$VERSION

  Existing Sparkle-enabled installs check the feed daily and will offer the
  update; you can force a check with "Check for Updates…" in the app menu.
  Installs older than the first Sparkle release must be updated manually once.

  Local smoke test (two signed versions required):
    fresh install this DMG in /Applications, then build the next version with
    MW_UPDATE_FEED_URL pointing at a local appcast (see README → Auto-updates).
EOF
else
    echo
    echo "✓ Release $VERSION ($BUILD_NUMBER) built in dist/ (not published)."
fi
