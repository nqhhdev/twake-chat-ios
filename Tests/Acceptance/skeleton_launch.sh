#!/usr/bin/env bash
# Runtime acceptance checks for TWAK-34, added by the tester next to skeleton.sh and skeleton_manifests.sh.
# Those scripts prove the project builds; this one proves the built app runs:
#   - the Release configuration builds with no warning (VALIDATE_PRODUCT, whole-module), not only Debug;
#   - on an iOS 26 simulator the app installs, launches, stays running, and shows a blank screen
#     (no screen content, card "Out of scope"). Owner decision 2026-11-12: iOS 26 only, no iOS 18 launch check.
#
# Usage, from the repository root:
#   Tests/Acceptance/skeleton_launch.sh
# The script creates a new, disposable iPhone simulator from the installed iOS 26 runtime and deletes it on exit.
# It never installs into, uninstalls from or erases a simulator it did not create.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/twak34-launch.XXXXXX")"
CREATED=()
cleanup() {
  for u in ${CREATED[@]+"${CREATED[@]}"}; do
    xcrun simctl shutdown "$u" >/dev/null 2>&1
    xcrun simctl delete "$u" >/dev/null 2>&1
  done
  rm -rf "$WORK"
}
trap cleanup EXIT

FAILURES=0
pass() { printf 'ok   %s\n' "$1"; }
fail() { printf 'FAIL %s\n' "$1"; FAILURES=$((FAILURES + 1)); }

BUNDLE_ID=app.twake.ios.chat

# ---------------------------------------------------------------- Release build
log="$WORK/release.log"
if xcodebuild build -project TwakeChat.xcodeproj -scheme TwakeChat -configuration Release \
     -destination 'generic/platform=iOS Simulator' -derivedDataPath "$WORK/dd-release" >"$log" 2>&1 \
   && grep -q '\*\* BUILD SUCCEEDED \*\*' "$log" && ! grep -q 'warning:' "$log"; then
  pass "Release configuration, generic iOS Simulator: BUILD SUCCEEDED, no warning"
else
  grep -E 'warning:|error:' "$log" | sort -u | head -20 >&2
  fail "Release configuration, generic iOS Simulator: failed or warned (log lines above)"
fi

# ---------------------------------------------------------------- launch on iOS 26
# Prints "<runtime id> <device type id>": the newest available iOS <major> runtime and an iPhone type it supports.
pick_runtime() {
  xcrun simctl list runtimes available -j 2>/dev/null | python3 -I -c '
import json, sys
major = sys.argv[1]
runtimes = [r for r in json.load(sys.stdin)["runtimes"]
            if r.get("platform") == "iOS" and r.get("isAvailable") and r["version"].split(".")[0] == major]
for r in sorted(runtimes, key=lambda r: [int(x) for x in r["version"].split(".")], reverse=True):
    for t in r.get("supportedDeviceTypes", []):
        if t.get("productFamily") == "iPhone":
            print(r["identifier"], t["identifier"]); sys.exit(0)
sys.exit(1)' "$1"
}

# Checks that the middle band of a PNG screenshot (below the status bar, above the home indicator) is one colour.
# Standard library only: decodes 8-bit RGB/RGBA PNGs, the format simctl writes.
blank_screen() {
  python3 -I - "$1" <<'PY'
import struct, sys, zlib
data = open(sys.argv[1], "rb").read()
assert data[:8] == b"\x89PNG\r\n\x1a\n", "not a PNG"
pos, idat, ihdr = 8, b"", None
while pos < len(data):
    length, kind = struct.unpack(">I4s", data[pos:pos + 8])
    body = data[pos + 8:pos + 8 + length]
    if kind == b"IHDR": ihdr = struct.unpack(">IIBBBBB", body)
    elif kind == b"IDAT": idat += body
    pos += 12 + length
width, height, depth, ctype, _, _, interlace = ihdr
assert depth == 8 and ctype in (2, 6) and interlace == 0, f"unsupported PNG (depth {depth}, colour type {ctype})"
bpp = 4 if ctype == 6 else 3
raw, stride = zlib.decompress(idat), width * bpp
rows, prev, i = [], bytearray(stride), 0
for _ in range(height):
    f, line = raw[i], bytearray(raw[i + 1:i + 1 + stride]); i += 1 + stride
    for x in range(stride):
        a = line[x - bpp] if x >= bpp else 0
        b = prev[x]; c = prev[x - bpp] if x >= bpp else 0
        if f == 1: line[x] = (line[x] + a) & 255
        elif f == 2: line[x] = (line[x] + b) & 255
        elif f == 3: line[x] = (line[x] + (a + b) // 2) & 255
        elif f == 4:
            p = a + b - c; pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
            line[x] = (line[x] + (a if pa <= pb and pa <= pc else b if pb <= pc else c)) & 255
    rows.append(bytes(line)); prev = line
colours = set()
for y in range(height * 15 // 100, height * 85 // 100):
    r = rows[y]
    for x in range(0, stride, bpp):
        colours.add(r[x:x + 3])
        if len(colours) > 1:
            print(f"more than one colour in the content area, e.g. {sorted(colours)[:2]}"); sys.exit(1)
print(f"content area is one colour {colours.pop().hex()} ({width}x{height})")
PY
}

launch_on() { # $1 label, $2 iOS major
  local label="$1" major="$2" udid spec
  spec="$(pick_runtime "$major")"
  if [ -z "$spec" ]; then fail "$label: no installed iOS $major simulator runtime with an iPhone device type"; return; fi
  # A new, disposable simulator: existing simulators and any Twake Chat data on them are never touched.
  udid="$(xcrun simctl create "TWAK-34 acceptance $label" ${spec#* } ${spec%% *} 2>/dev/null)"
  if [ -z "$udid" ]; then fail "$label: could not create a disposable simulator ($spec)"; return; fi
  CREATED+=("$udid")
  local log="$WORK/build-$label.log" dd="$WORK/dd-$label"
  if ! xcodebuild build -project TwakeChat.xcodeproj -scheme TwakeChat -destination "id=$udid" \
         -derivedDataPath "$dd" >"$log" 2>&1 || ! grep -q '\*\* BUILD SUCCEEDED \*\*' "$log" || grep -q 'warning:' "$log"; then
    grep -E 'warning:|error:' "$log" | sort -u | head -20 >&2
    fail "$label ($udid): xcodebuild failed or warned"; return
  fi
  pass "$label ($udid): BUILD SUCCEEDED, no warning"
  local app; app="$(find "$dd/Build/Products" -maxdepth 2 -name TwakeChat.app -type d | head -1)"
  if ! xcrun simctl bootstatus "$udid" -b >/dev/null 2>&1; then fail "$label: simulator did not boot"; return; fi
  if xcrun simctl install "$udid" "$app" >/dev/null 2>&1; then pass "$label: app installs"; else fail "$label: app does not install"; return; fi
  local out; out="$(xcrun simctl launch "$udid" "$BUNDLE_ID" 2>&1)"
  if printf '%s' "$out" | grep -qE "^$BUNDLE_ID: [0-9]+"; then pass "$label: app launches ($out)"; else fail "$label: launch failed ($out)"; return; fi
  sleep 3
  # Still running after launch: the root view did not crash.
  if xcrun simctl spawn "$udid" launchctl list 2>/dev/null | grep -q "UIKitApplication:$BUNDLE_ID"; then
    pass "$label: app is still running 3 s after launch"
  else
    fail "$label: app is not running 3 s after launch (crashed?)"
  fi
  local shot="$WORK/$label.png"
  if xcrun simctl io "$udid" screenshot --type=png "$shot" >/dev/null 2>&1; then
    local msg; msg="$(blank_screen "$shot" 2>&1)"
    if [ $? -eq 0 ]; then pass "$label: blank screen, $msg"; else fail "$label: screen is not blank: $msg"; fi
  else
    fail "$label: could not take a screenshot"
  fi
  xcrun simctl terminate "$udid" "$BUNDLE_ID" >/dev/null 2>&1
}

launch_on ios26 26

echo
if [ "$FAILURES" -eq 0 ]; then echo "skeleton launch: all checks passed"; exit 0; fi
echo "skeleton launch: $FAILURES check(s) failed"; exit 1
