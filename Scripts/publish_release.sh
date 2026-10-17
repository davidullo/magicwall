#!/usr/bin/env bash
#
# One-command release for MagicWall.
#
#   ./Scripts/publish                 # next patch  (0.2.0 → 0.2.1)
#   ./Scripts/publish minor           # next minor  (0.2.0 → 0.3.0)
#   ./Scripts/publish major           # next major  (0.2.0 → 1.0.0)
#   ./Scripts/publish 1.2.3           # exact version
#   ./Scripts/publish --dry-run       # show the plan without touching anything
#
# The signing identity is detected from the keychain, the notary profile
# defaults to "magicwall", the build number is current + 1: no other input is
# needed. Without --yes the release starts after a short countdown, so a wrong
# invocation can be aborted with Ctrl-C.
#
# What it does, in order:
#   1. resolves the version and validates the environment (Developer ID,
#      notary profile, gh auth, release not already published);
#   2. bumps MARKETING_VERSION / CURRENT_PROJECT_VERSION in project.yml;
#   3. runs the MagicWallCore tests;
#   4. commits all pending changes as "Release v<version>" and pushes;
#   5. calls Scripts/release.sh --notarize [--publish] (universal build,
#      Developer ID signing incl. Sparkle helpers, notarization, DMG/ZIP/dSYM,
#      signed appcast);
#   6. verifies the published feed (new build number + EdDSA signature).
#
# Options:
#   --build N        explicit build number (default: current + 1)
#   --yes            start immediately, no countdown
#   --dry-run        validate and print the plan, then stop
#   --skip-tests     skip the core test suite
#   --with-e2e       also run the XCUITest suite before building
#   --no-publish     build, sign, notarize and generate the appcast, but do
#                    not create the GitHub release (the version bump is still
#                    committed and pushed unless --no-commit/--no-push)
#   --no-push        commit locally but do not push
#   --no-commit      do not touch git at all
#
# Environment (normally auto-detected):
#   SIGN_IDENTITY    "Developer ID Application: Name (TEAMID)"
#   NOTARY_PROFILE   notarytool keychain profile (default: magicwall)
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

VERSION_ARG=""
BUILD_NUMBER=""
ASSUME_YES=0
DRY_RUN=0
RUN_TESTS=1
RUN_E2E=0
PUBLISH=1
PUSH=1
COMMIT=1

usage() {
    sed -n '2,46p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --build) BUILD_NUMBER="$2"; shift 2 ;;
        --yes|-y) ASSUME_YES=1; shift ;;
        --dry-run) DRY_RUN=1; shift ;;
        --skip-tests) RUN_TESTS=0; shift ;;
        --with-e2e) RUN_E2E=1; shift ;;
        --no-publish) PUBLISH=0; shift ;;
        --no-push) PUSH=0; shift ;;
        --no-commit) COMMIT=0; shift ;;
        -h|--help) usage ;;
        -*) echo "Unknown option: $1" >&2; usage ;;
        *)
            if [[ -n "$VERSION_ARG" ]]; then
                echo "Only one version argument is allowed." >&2
                exit 1
            fi
            VERSION_ARG="$1"; shift ;;
    esac
done

# ------------------------------------------------------------ current state

CURRENT_VERSION="$(sed -n 's/^[[:space:]]*MARKETING_VERSION: "\(.*\)"$/\1/p' project.yml | head -1)"
CURRENT_BUILD="$(sed -n 's/^[[:space:]]*CURRENT_PROJECT_VERSION: "\(.*\)"$/\1/p' project.yml | head -1)"

if [[ "$CURRENT_VERSION" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
    # BASH_REMATCH is clobbered by the next regex match: capture right away.
    MAJOR="${BASH_REMATCH[1]}"
    MINOR="${BASH_REMATCH[2]}"
    PATCH="${BASH_REMATCH[3]}"
else
    echo "Unexpected MARKETING_VERSION in project.yml: $CURRENT_VERSION" >&2
    exit 1
fi

if [[ ! "$CURRENT_BUILD" =~ ^[0-9]+$ ]]; then
    echo "Unexpected CURRENT_PROJECT_VERSION in project.yml: $CURRENT_BUILD" >&2
    exit 1
fi

# -------------------------------------------------------------- next version

VERSION_ARG="${VERSION_ARG:-patch}"

case "$VERSION_ARG" in
    patch)   VERSION="$MAJOR.$MINOR.$((PATCH + 1))" ;;
    minor)   VERSION="$MAJOR.$((MINOR + 1)).0" ;;
    major)   VERSION="$((MAJOR + 1)).0.0" ;;
    *)
        if [[ ! "$VERSION_ARG" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            echo "Version must be patch, minor, major or X.Y.Z (got: $VERSION_ARG)." >&2
            exit 1
        fi
        VERSION="$VERSION_ARG" ;;
esac

if [[ "$VERSION" == "$CURRENT_VERSION" ]]; then
    echo "project.yml is already at $VERSION." >&2
    exit 1
fi

if [[ -z "$BUILD_NUMBER" ]]; then
    BUILD_NUMBER="$((CURRENT_BUILD + 1))"
fi

if [[ ! "$BUILD_NUMBER" =~ ^[0-9]+$ ]] || (( BUILD_NUMBER <= CURRENT_BUILD )); then
    echo "Build number must be an integer greater than $CURRENT_BUILD (got: $BUILD_NUMBER)." >&2
    exit 1
fi

# -------------------------------------------------------------- environment

if [[ -z "${SIGN_IDENTITY:-}" || "${SIGN_IDENTITY}" == "-" ]]; then
    SIGN_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
        | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' \
        | head -1)"
fi

if [[ -z "${SIGN_IDENTITY:-}" ]]; then
    echo 'No Developer ID Application identity found in the keychain.' >&2
    echo 'Set SIGN_IDENTITY="Developer ID Application: Name (TEAMID)".' >&2
    exit 1
fi

NOTARY_PROFILE="${NOTARY_PROFILE:-magicwall}"

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
    if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
        echo "Notary profile '$NOTARY_PROFILE' not found in the keychain." >&2
        echo "Create it with: xcrun notarytool store-credentials $NOTARY_PROFILE --apple-id ... --team-id ..." >&2
        exit 1
    fi
fi

# ------------------------------------------------------------------- plan

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

if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "  Dry run: nothing was changed."
    exit 0
fi

if [[ "$ASSUME_YES" -ne 1 ]]; then
    echo "  Starting in 8 seconds — press Ctrl-C to abort."
    for i in 8 7 6 5 4 3 2 1; do
        printf "\r  %d…" "$i"
        sleep 1
    done
    printf "\r  Going.\n"
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
    for attempt in 1 2 3 4 5 6 7 8 9 10; do
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
        echo "⚠ The feed does not expose build $BUILD_NUMBER yet. Check the assets:" >&2
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

  Next time:
    ./Scripts/publish            # patch
    ./Scripts/publish minor      # feature release
EOF
else
    echo
    echo "✓ Release $VERSION ($BUILD_NUMBER) built in dist/ (not published)."
fi
