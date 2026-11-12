#!/bin/bash
# Runs every unit test and stops with a non-zero exit code on the first failure.
#   1. `swift test` in Packages/Domain and Packages/AppShared, on the macOS host (no simulator).
#   2. `xcodebuild test` with the TwakeChat test plan (TwakeChatTests, DesignSystemTests, MatrixDataTests)
#      on one iOS 26 simulator.
# Usage: scripts/test.sh
#        SIMULATOR_NAME='iPhone 17 Pro' scripts/test.sh    any installed iOS 26.x simulator; default iPhone 17
set -euo pipefail

cd "$(dirname "$0")/.."

SIMULATOR_NAME="${SIMULATOR_NAME:-iPhone 17}"

host_start=$SECONDS
for package in Packages/Domain Packages/AppShared; do
  echo "==> swift test --package-path $package"
  swift test --package-path "$package"
done
echo "==> Host tests passed in $((SECONDS - host_start)) s"

# The id of the first available simulator with that name under an iOS 26.x runtime.
simulator_id="$(xcrun simctl list devices available | awk -v name="$SIMULATOR_NAME" '
  /^-- / { ios26 = ($0 ~ /^-- iOS 26\./); next }
  ios26 && index($0, "    " name " (") == 1 {
    if (match($0, /\([0-9A-F-]{36}\)/)) { print substr($0, RSTART + 1, RLENGTH - 2); exit }
  }')"
if [ -z "$simulator_id" ]; then
  echo "error: no available iOS 26 simulator named '$SIMULATOR_NAME'." >&2
  echo "Set SIMULATOR_NAME to one listed under '-- iOS 26.x --' by: xcrun simctl list devices available" >&2
  exit 1
fi

echo "==> xcodebuild test, test plan TwakeChat, $SIMULATOR_NAME (iOS 26, $simulator_id)"
xcodebuild test \
  -project TwakeChat.xcodeproj \
  -scheme TwakeChat \
  -testPlan TwakeChat \
  -destination "platform=iOS Simulator,id=$simulator_id"
