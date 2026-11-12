#!/bin/bash
# Tests scripts/test.sh (TWAK-35) without Xcode: each case copies test.sh into a throwaway tree under $TMPDIR
# and puts stub `swift`, `xcrun` and `xcodebuild` commands first on PATH. The stubs record their calls and
# fail when told to. Exits non-zero if any case fails.
set -uo pipefail

repo="$(cd "$(dirname "$0")/../.." && pwd)"
work="$(mktemp -d "${TMPDIR:-/tmp}/test_test.XXXXXX")"
trap 'rm -rf "$work"' EXIT

failures=0
cases=0

# What `xcrun simctl list devices available` prints: an iPhone 17 under iOS 26.0 and under iOS 27.2.
cat > "$work/simctl.txt" <<'EOF'
== Devices ==
-- iOS 26.0 --
    iPhone 17 Pro (70FD0C3C-E0E2-4720-A270-E2FACE11D055) (Shutdown)
    iPhone 17 (F9559607-AC2C-41AF-B42B-015C217AA835) (Shutdown)
-- iOS 27.2 --
    iPhone 17 (AB386725-6242-4630-B585-DCA9089956E4) (Shutdown)
    iPhone 18 Pro (4097F41F-6FCC-4BA6-AE65-917BE1660B8B) (Booted)
EOF

mkdir -p "$work/bin"
# Each stub appends its arguments to $CALLS, its working directory to $CALLS.pwd,
# and exits 1 when $FAIL_ON matches them.
for tool in swift xcodebuild; do
  cat > "$work/bin/$tool" <<EOF
#!/bin/bash
echo "$tool \$*" >> "\$CALLS"
pwd -P >> "\$CALLS.pwd"
case "$tool \$*" in \$FAIL_ON) exit 1 ;; esac
exit 0
EOF
done
cat > "$work/bin/xcrun" <<EOF
#!/bin/bash
[ "\$*" = "simctl list devices available" ] && cat "\${SIMCTL_LIST:-$work/simctl.txt}" && exit 0
echo "unexpected xcrun \$*" >&2; exit 2
EOF
chmod +x "$work/bin/"*

# run_case <name> <FAIL_ON pattern> [VAR=value ...]: runs a copy of test.sh; sets $status and $calls.
run_case() {
  local dir="$work/$1" fail_on="$2"; shift 2
  mkdir -p "$dir/scripts"
  cp "$repo/scripts/test.sh" "$dir/scripts/test.sh"
  : > "$dir/calls"
  env PATH="$work/bin:$PATH" CALLS="$dir/calls" FAIL_ON="$fail_on" "$@" \
    bash "$dir/scripts/test.sh" > "$dir/out" 2>&1
  status=$?
  calls="$(cat "$dir/calls")"
}

expect() {  # expect <case name> <description> <condition...>
  local name="$1" what="$2"; shift 2
  cases=$((cases + 1))
  if "$@"; then echo "ok   $name: $what"; else echo "FAIL $name: $what"; failures=$((failures + 1)); fi
}

all="swift test --package-path Packages/Domain
swift test --package-path Packages/AppShared
xcodebuild test -project TwakeChat.xcodeproj -scheme TwakeChat -testPlan TwakeChat -destination platform=iOS Simulator,id=F9559607-AC2C-41AF-B42B-015C217AA835"

run_case pass 'none'
expect pass "exits 0" test "$status" -eq 0
expect pass "runs both host packages, then the test plan on the iOS 26 iPhone 17" test "$calls" = "$all"
# run_case starts test.sh from this script's working directory, not from the copy's root, so this shows the cd.
expect pass "runs every tool from the repository root, wherever it is started" bash -c \
  "[ \"\$(sort -u '$work/pass/calls.pwd')\" = \"\$(cd '$work/pass' && pwd -P)\" ]"
expect pass "prints how long the host-only part took" grep -qE '^==> Host tests passed in [0-9]+ s$' "$work/pass/out"

run_case domain-fails 'swift test --package-path Packages/Domain'
expect domain-fails "exits non-zero" test "$status" -ne 0
expect domain-fails "runs nothing after Domain" test "$calls" = "swift test --package-path Packages/Domain"

run_case appshared-fails 'swift test --package-path Packages/AppShared'
expect appshared-fails "exits non-zero" test "$status" -ne 0
expect appshared-fails "does not run xcodebuild" bash -c "! grep -q xcodebuild '$work/appshared-fails/calls'"

run_case xcodebuild-fails 'xcodebuild*'
expect xcodebuild-fails "exits non-zero" test "$status" -ne 0

run_case other-name 'none' SIMULATOR_NAME='iPhone 17 Pro'
expect other-name "SIMULATOR_NAME picks that iOS 26 simulator" \
  grep -q 'id=70FD0C3C-E0E2-4720-A270-E2FACE11D055$' "$work/other-name/calls"

run_case not-ios26 'none' SIMULATOR_NAME='iPhone 18 Pro'
expect not-ios26 "a simulator that exists only outside iOS 26 exits non-zero" test "$status" -ne 0
expect not-ios26 "and does not run xcodebuild" bash -c "! grep -q xcodebuild '$work/not-ios26/calls'"
expect not-ios26 "and names the simulator in the error" grep -q "no available iOS 26 simulator named 'iPhone 18 Pro'" "$work/not-ios26/out"

run_case unknown-name 'none' SIMULATOR_NAME='iPhone 99'
expect unknown-name "a simulator name that exists nowhere exits non-zero" test "$status" -ne 0
expect unknown-name "and runs nothing after the host tests" bash -c "! grep -q xcodebuild '$work/unknown-name/calls'"

# The shape of a real list: a custom device whose name contains "iPhone 17" comes first, an iOS 26.x runtime
# with no device, and the same runtime header twice. Only the exact name under an iOS 26 runtime may match.
cat > "$work/simctl-real.txt" <<'EOF'
== Devices ==
-- iOS 26.0 --
    iPhone 17 Pro Max (BC9BF20C-0150-411C-8718-3400D4C0D9AF) (Shutdown)
    Team iPhone 17 iOS 26 (714479B5-069D-4F90-8055-31F7C4F6A9F4) (Shutdown)
    iPhone 17 (F9559607-AC2C-41AF-B42B-015C217AA835) (Shutdown)
-- iOS 26.3 --
-- iOS 27.2 --
    iPhone Duo (2B6EAE51-95E6-4D7D-8DF2-0BB9023B632F) (Booted)
-- iOS 27.2 --
    iPhone 17 (AB386725-6242-4630-B585-DCA9089956E4) (Shutdown)
EOF
run_case real-list 'none' SIMCTL_LIST="$work/simctl-real.txt"
expect real-list "exits 0" test "$status" -eq 0
expect real-list "picks the exact name under iOS 26, not a longer name containing it" \
  grep -q 'id=F9559607-AC2C-41AF-B42B-015C217AA835$' "$work/real-list/calls"

echo "$((cases - failures))/$cases passed"
[ "$failures" -eq 0 ]
