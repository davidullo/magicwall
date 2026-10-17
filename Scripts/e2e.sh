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
#   - A non-empty library for the preview tests. Import fixtures with:
#       Packages/MagicWallCore/.build/debug/mwctl import <files...>
#     (see "Dev tools" in README.md).
set -euo pipefail

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
cd "$(dirname "$0")/.."

# Serialize project generation with other tooling (agents, Xcode).
LOCK=/tmp/mw-xcodegen.lock
while ! mkdir "$LOCK" 2>/dev/null; do sleep 1; done
xcodegen generate >/dev/null
rmdir "$LOCK"

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
