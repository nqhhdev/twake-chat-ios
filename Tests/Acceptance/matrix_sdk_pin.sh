#!/usr/bin/env bash
# Acceptance checks for TWAK-48 (matrix-rust-components-swift 26.04.01 in MatrixData, and its API page), added by
# the tester. skeleton.sh and skeleton_manifests.sh already check the manifest pin and the import boundary; this
# script checks what they do not: both Package.resolved files, and that every API name on the reference page is
# cited at a line of the resolved checkout that really declares it (ADR 0003, ADR 0015).
#
# Usage, from the repository root:
#   Tests/Acceptance/matrix_sdk_pin.sh
# The citation checks need the checkout. If Packages/MatrixData/.build/checkouts is missing, the script runs
# `swift package resolve --package-path Packages/MatrixData` once (network or the SwiftPM cache).
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

FAILURES=0
pass() { printf 'ok   %s\n' "$1"; }
fail() { printf 'FAIL %s\n' "$1"; FAILURES=$((FAILURES + 1)); }
check() { local name="$1"; shift; if "$@" >/dev/null 2>&1; then pass "$name"; else fail "$name"; fi; }

TAG=26.04.01
SDK_URL=https://github.com/matrix-org/matrix-rust-components-swift
PACKAGE_RESOLVED=Packages/MatrixData/Package.resolved
WORKSPACE_RESOLVED=TwakeChat.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
PAGE="${PAGE:-.okf/references/matrix-sdk-26-04-01-api.md}"
CHECKOUT=Packages/MatrixData/.build/checkouts/matrix-rust-components-swift

# ---------------------------------------------------------------- Package.resolved
# SwiftPM writes the tag 26.04.01 as the version 26.4.1. The file must pin the SDK and nothing else remote.
resolved_pins_sdk() {
  python3 -I - "$1" "$SDK_URL" <<'PY'
import json, sys
path, url = sys.argv[1], sys.argv[2]
pins = json.load(open(path))["pins"]
sdk = [p for p in pins if p["identity"] == "matrix-rust-components-swift"]
ok = (len(pins) == 1 and len(sdk) == 1 and sdk[0]["location"] == url
      and sdk[0]["kind"] == "remoteSourceControl" and sdk[0]["state"].get("version") == "26.4.1"
      and len(sdk[0]["state"].get("revision", "")) == 40)
sys.exit(0 if ok else 1)
PY
}
revision_of() { python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))["pins"][0]["state"]["revision"])' "$1" 2>/dev/null; }

# The builder does not commit, so the file must exist and must not be ignored (it is committed with the card).
check "$PACKAGE_RESOLVED exists and is not ignored by git" bash -c \
  "[ -f '$PACKAGE_RESOLVED' ] && ! git check-ignore -q '$PACKAGE_RESOLVED'"
check "$PACKAGE_RESOLVED pins only matrix-rust-components-swift, version 26.4.1 (tag $TAG)" \
  resolved_pins_sdk "$PACKAGE_RESOLVED"
# Xcode 27.2 writes no workspace Package.resolved for this project: the SDK is reached only through the local
# MatrixData package (checked with xcodebuild -resolvePackageDependencies and a full xcodebuild test, TWAK-48).
# If a later Xcode writes one, it must pin the same SDK at the same revision.
check "$WORKSPACE_RESOLVED is not ignored by git" bash -c "! git check-ignore -q --no-index '$WORKSPACE_RESOLVED'"
if [ -f "$WORKSPACE_RESOLVED" ]; then
  check "$WORKSPACE_RESOLVED pins only matrix-rust-components-swift, version 26.4.1" resolved_pins_sdk "$WORKSPACE_RESOLVED"
  a="$(revision_of "$PACKAGE_RESOLVED")"; b="$(revision_of "$WORKSPACE_RESOLVED")"
  [ -n "$a" ] && [ "$a" = "$b" ] && pass "both Package.resolved files pin the same revision ($a)" \
    || fail "both Package.resolved files pin the same revision (package '$a', workspace '$b')"
fi
# No other committed or to-be-committed Package.resolved may pin the SDK (ADR 0006: one package owns it).
others="$({ git ls-files '*Package.resolved'; git ls-files --others --exclude-standard '*Package.resolved'; } | grep -vxF -e "$PACKAGE_RESOLVED" -e "$WORKSPACE_RESOLVED" \
  | xargs -r grep -l 'matrix-rust-components-swift' 2>/dev/null)"
[ -z "$others" ] && pass "no other committed Package.resolved pins the SDK" || fail "other Package.resolved pin the SDK: $others"

# ---------------------------------------------------------------- import boundary and no placeholder
# skeleton.sh searches TwakeChat and Packages only; the project's test bundles live in Tests/ (ADR 0006: only MatrixData
# imports the SDK, so its tests reach it only through MatrixData's public API).
SDK_IMPORT='import[[:space:]]+(MatrixRustSDK|MatrixRustComponents|MatrixSDK|MatrixSDKFFI|MatrixSDKCrypto)([^A-Za-z0-9_]|$)'
check "no Matrix SDK import in Tests/ (MatrixDataTests, TwakeChatTests)" bash -c \
  "! grep -rnE --include='*.swift' '$SDK_IMPORT' Tests"
# @_exported would hand every SDK type to Domain's and the app's importers of MatrixData (ADR 0006).
check "MatrixData does not re-export the SDK (@_exported)" bash -c \
  "! grep -rnE --include='*.swift' '@_exported' Packages/MatrixData/Sources"
# ADR 0011 and the card: no placeholder. The module marker file declares only MatrixDataModule. TWAK-64 narrowed this
# check from all of MatrixData's sources to the marker file, because ClientProxy and MatrixAuthenticationRepository now
# exist beside it (proxies arrive with the features that need them, ADR 0006).
decls="$(grep -hE '^[[:space:]]*(public |internal |private |fileprivate |package |open |static |final )*(class|struct|enum|protocol|actor|extension|typealias|func|let|var)[[:space:]]' Packages/MatrixData/Sources/MatrixData/MatrixData.swift | sed -E 's/[[:space:]]*\{.*//; s/^[[:space:]]+//')"
expected="$(printf '%s\n' 'public enum MatrixDataModule' 'public static let dependencies = [DomainModule.name, AppSharedModule.name]')"
[ "$decls" = "$expected" ] && pass "MatrixData.swift declares only MatrixDataModule and its dependencies (no placeholder)" \
  || fail "MatrixData.swift declares more than its module marker: $(printf '%s' "$decls" | tr '\n' ';')"

# ---------------------------------------------------------------- the checkout is the tag
if [ ! -d "$CHECKOUT" ]; then
  echo "note: $CHECKOUT missing, running swift package resolve" >&2
  swift package resolve --package-path Packages/MatrixData >/dev/null 2>&1
fi
PIN="$(revision_of "$PACKAGE_RESOLVED")"
check "the checkout exists ($CHECKOUT)" test -f "$CHECKOUT/Sources/MatrixRustSDK/matrix_sdk_ffi.swift"
check "the checkout is at the pinned revision" bash -c "[ \"\$(git -C '$CHECKOUT' rev-parse HEAD)\" = '$PIN' ]"
check "the pinned revision is the commit of tag $TAG" bash -c \
  "[ \"\$(git -C '$CHECKOUT' rev-parse '$TAG^{commit}')\" = '$PIN' ]"

# ADR 0006: no public or open declaration anywhere in MatrixData's sources names a type the pinned SDK declares
# (TWAK-64 narrowed the marker check above, so this covers ClientProxy, the repository and every later file).
python3 -I - "$CHECKOUT/Sources/MatrixRustSDK" Packages/MatrixData/Sources <<'PY'
import os, re, sys
sdk_dir, src_dir = sys.argv[1], sys.argv[2]
names = set()
for f in os.listdir(sdk_dir):
    if f.endswith(".swift"):
        names |= set(re.findall(r"^\s*(?:public|open)\s+(?:final\s+)?(?:class|struct|enum|protocol|typealias)\s+(\w+)",
                                open(os.path.join(sdk_dir, f)).read(), re.M))
bad = []
for root, _, files in os.walk(src_dir):
    for f in files:
        if not f.endswith(".swift"): continue
        path = os.path.join(root, f)
        for n, line in enumerate(open(path), 1):
            if re.match(r"^\s*(?:@\w+\s+)*(?:public|open)\b", line):
                # A name qualified with Domain. is the Domain type of that name (TWAK-66: Domain.RoomListError, which
                # the SDK also declares), not the SDK's.
                code = re.sub(r"\bDomain\.\w+", "", line.split("//")[0])
                hit = sorted(set(re.findall(r"\w+", code)) & names)
                if hit: bad.append(f"{path}:{n} {hit}")
ok = len(names) > 100
print(("ok   " if ok and not bad else "FAIL ") + f"MatrixData public declarations name no SDK type ({len(names)} SDK types)"
      + ("" if not bad else ": " + "; ".join(bad)))
sys.exit(0 if ok and not bad else 1)
PY
[ $? -eq 0 ] || FAILURES=$((FAILURES + 1))

# ---------------------------------------------------------------- the API page
check "$PAGE exists" test -f "$PAGE"
check "the page names the pinned revision" grep -qF "$PIN" "$PAGE"
check "Data Layer links the page" grep -qF '(../../references/matrix-sdk-26-04-01-api.md)' .okf/architecture/components/data.md
check "References index links the page" grep -qF '(matrix-sdk-26-04-01-api.md)' .okf/references/index.md
check "Data Layer itself names no SDK class (version-neutral page)" bash -c \
  "! grep -qE 'ClientBuilder|RoomListService|TimelineListener|startSsoLogin|crossProcessLockConfig' .okf/architecture/components/data.md"

# Every number the page cites (the Line column, and 'class at line N' / 'protocol at N' notes) must land on a line of
# matrix_sdk_ffi.swift that declares one of the names written in backticks on the same table row or heading.
python3 -I - "$PAGE" "$CHECKOUT/Sources/MatrixRustSDK/matrix_sdk_ffi.swift" <<'PY'
import re, sys
page, source = sys.argv[1], sys.argv[2]
try:
    src = open(source).read().split("\n")
except OSError:
    print("FAIL citations: checkout source not readable"); sys.exit(1)
bad = 0
def report(ok, msg):
    global bad
    print(("ok   " if ok else "FAIL ") + msg); bad += 0 if ok else 1
decl = re.compile(r"^\s*(?:(?:open|public|private|internal)\s+)*(?:convenience\s+)?"
                  r"(?:func|class|enum|protocol|struct|case|var|let)\s+(\w+)|^\s*(?:public\s+)?(?:convenience\s+)?(init)\(")
def numbers(text):
    out = []
    for a, b in re.findall(r"(\d{3,})(?:-(\d{3,}))?", text):
        out.append(int(a))
        if b: out.append(int(b))
    return out
sections = {"Building a client", "Login, session", "SSO login-token flow", "Sync and room list", "Timeline and sending"}
in_api, rows, cited = False, 0, 0
for raw in open(page).read().split("\n"):
    line = raw.strip()
    if line.startswith("## "):
        in_api = any(s in line for s in sections)
        nums = [int(n) for n in re.findall(r"line (\d+)", line)]
        names = set(re.findall(r"\w+", " ".join(re.findall(r"`([^`]*)`", line))))
        for n in nums:
            m = decl.match(src[n - 1]) if n <= len(src) else None
            got = m and (m.group(1) or m.group(2))
            report(bool(got) and got in names, f"heading cites line {n}: declares {got!r}, page names {sorted(names)}")
            cited += 1
        continue
    if not in_api or not line.startswith("|") or line.startswith("|---") or line.startswith("| What"):
        continue
    cells = [c.strip() for c in line.strip("|").split("|")]
    what, sig, line_col = cells[0], " | ".join(cells[1:-1]), cells[-1]
    rows += 1
    names = set(re.findall(r"\w+", " ".join(re.findall(r"`([^`]*)`", what + " " + sig))))
    nums = numbers(line_col) + [int(n) for n in re.findall(r"(?:line|at) (\d{3,})", sig)]
    if not nums:
        report(False, f"row '{what}' has no line citation"); continue
    for n in nums:
        m = decl.match(src[n - 1]) if 0 < n <= len(src) else None
        got = m and (m.group(1) or m.group(2))
        report(bool(got) and got in names, f"row '{what}' line {n}: declares {got!r}")
        cited += 1
report(rows >= 40, f"the page has {rows} cited API rows (the six areas need at least 40)")
sys.exit(1 if bad else 0)
PY
[ $? -eq 0 ] || FAILURES=$((FAILURES + 1))

# The card's six areas and the two open questions each appear on the page.
for name in serverNameOrHomeserverUrl sessionPaths slidingSyncVersionBuilder 'login(username' restoreSession logout \
            RoomListService RoomListEntriesListener RoomListEntriesUpdate 'timeline()' TimelineListener TimelineDiff \
            'send(msg' messageEventContentFromMarkdown startSsoLogin crossProcessLockConfig; do
  check "the page records $name" grep -qF "$name" "$PAGE"
done

# ---------------------------------------------------------------- Open Verifications and log
OV=.okf/backlog/open-verifications.md
check "Open Verifications row 2 records the SSO and lock APIs as found but not yet run" bash -c \
  "grep -F 'SSO login-token flow' '$OV' | grep -F startSsoLogin | grep -F crossProcessLockConfig | grep -qiE 'not yet run|not run'"
check "Open Verifications row 1 (sliding sync on every deployment) stays open: still says to ask the server team" bash -c \
  "grep -F 'Every deployment to support has sliding sync' '$OV' | grep -qF 'Ask the server team'"
check "log.md has a line for TWAK-48" grep -q 'TWAK-48' .okf/log.md

echo
if [ "$FAILURES" -eq 0 ]; then echo "matrix sdk pin acceptance: all checks passed"; exit 0; fi
echo "matrix sdk pin acceptance: $FAILURES check(s) failed"; exit 1
