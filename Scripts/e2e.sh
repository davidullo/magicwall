#!/usr/bin/env bash
#
# End-to-end UI tests for MagicWall.
#
#   ./Scripts/e2e.sh                          # run all UI tests
#   ./Scripts/e2e.sh -only-testing:MagicWallUITests/testSidebarIsComplete
#
# Requirements:
#   - Xcode installed (DEVELOPER_DIR can be overridden)
#   - Accessibility permission for the test runner: the first run may prompt,
#     or grant it manually in System Settings → Privacy & Security →
#     Accessibility / Automation (Xcode and your terminal app).
#
# The script also prepares an isolated library in a temporary directory:
# a generated test video is imported with mwctl and the path is exported as
# MW_E2E_SEEDED_DATA_DIR. The app receives the same path through
# MAGICWALL_DATA_DIR, so UI tests never touch the real user library.
set -euo pipefail

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
cd "$(dirname "$0")/.."

# Serialize project generation with other tooling (agents, Xcode).
LOCK=/tmp/mw-xcodegen.lock
while ! mkdir "$LOCK" 2>/dev/null; do sleep 1; done
xcodegen generate >/dev/null
rmdir "$LOCK"

# Isolated E2E library (fresh on every run). Keep the path in sync with
# MW_E2E_SEEDED_DATA_DIR in project.yml: the test runner cannot see the shell
# environment, so the seeded directory is passed through the scheme.
E2E_DATA_ROOT="/tmp/mw-e2e-data"
SEEDED_DATA_DIR="$E2E_DATA_ROOT/seeded"
rm -rf "$E2E_DATA_ROOT"
mkdir -p "$SEEDED_DATA_DIR"

# Build mwctl and import a generated fixture into the isolated library.
swift build --package-path Packages/MagicWallCore --product mwctl >/dev/null
MWCTL_BIN_DIR="$(swift build --package-path Packages/MagicWallCore --show-bin-path)"
FIXTURE="$E2E_DATA_ROOT/test-pattern.mp4"
swift DevTools/make-test-video.swift "$FIXTURE" >/dev/null
MAGICWALL_DATA_DIR="$SEEDED_DATA_DIR" "$MWCTL_BIN_DIR/mwctl" import "$FIXTURE" >/dev/null
MAGICWALL_DATA_DIR="$SEEDED_DATA_DIR" "$MWCTL_BIN_DIR/mwctl" favorite-latest >/dev/null
export MW_E2E_SEEDED_DATA_DIR="$SEEDED_DATA_DIR"

EXTRA_ARGS=("$@")
if [ ${#EXTRA_ARGS[@]} -eq 0 ]; then
    EXTRA_ARGS=(-only-testing:MagicWallUITests)
fi

set +e
xcodebuild \
    -project MagicWall.xcodeproj \
    -scheme MagicWall \
    -configuration Debug \
    -derivedDataPath /tmp/mw-dd-e2e \
    test "${EXTRA_ARGS[@]}" \
    2>&1 | tee /tmp/mw-e2e.log | grep -E "Test Suite|Test Case|error:|failed|passed|TEST" | tail -50
STATUS=${PIPESTATUS[0]}

echo
echo "Full log: /tmp/mw-e2e.log"
if [ "$STATUS" -ne 0 ]; then
    echo "E2E FAILED (exit $STATUS)"
    exit "$STATUS"
fi
echo "E2E PASSED"
