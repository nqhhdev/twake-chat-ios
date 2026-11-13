#!/usr/bin/env bash
# Acceptance checks for TWAK-35 (unit test targets and one test command), added by the tester.
# Text checks only, no Xcode needed. scripts/tests/test_test.sh covers how scripts/test.sh behaves;
# this script covers what it runs: the test plan, the scheme, and the test files (ADR 0010, naming.md).
#
# Usage, from the repository root:
#   Tests/Acceptance/test_harness.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

FAILURES=0
pass() { printf 'ok   %s\n' "$1"; }
fail() { printf 'FAIL %s\n' "$1"; FAILURES=$((FAILURES + 1)); }
check() { local name="$1"; shift; if "$@" >/dev/null 2>&1; then pass "$name"; else fail "$name"; fi; }

PBX=TwakeChat.xcodeproj/project.pbxproj
SCHEME=TwakeChat.xcodeproj/xcshareddata/xcschemes/TwakeChat.xcscheme
PLAN=TwakeChat.xctestplan

# ---------------------------------------------------------------- scripts/test.sh
check "scripts/test.sh is executable" test -x scripts/test.sh
check "scripts/test.sh stops on the first failure (set -euo pipefail)" grep -qE '^set -euo pipefail' scripts/test.sh
check "scripts/test.sh runs swift test for Domain and AppShared only on the host" bash -c \
  "grep -qE '^for package in Packages/Domain Packages/AppShared; do' scripts/test.sh"

# ---------------------------------------------------------------- test plan and scheme
# The plan lists the three simulator targets and leaves out Domain and AppShared, so they do not run twice.
# The id of the PBXNativeTarget named TwakeChatTests (the synchronized folder of the same name is a different object).
target_id() { grep -B1 'isa = PBXNativeTarget;' "$PBX" | grep -E "/\\* $1 \\*/ = \\{" | grep -oE '[0-9A-F]{24}' | head -1; }
tests_id="$(target_id TwakeChatTests)"
matrix_id="$(target_id MatrixDataTests)"
python3 -I - "$PLAN" "$tests_id" "$matrix_id" <<'PY'
import json, sys
path, tests_id, matrix_id = sys.argv[1], sys.argv[2], sys.argv[3]
bad = 0
def report(ok, msg):
    global bad
    print(("ok   " if ok else "FAIL ") + msg); bad += 0 if ok else 1
try:
    plan = json.load(open(path))
except Exception as e:
    report(False, f"{path} is valid JSON ({e})"); sys.exit(1)
targets = [t["target"] for t in plan.get("testTargets", [])]
got = sorted((t["name"], t["containerPath"]) for t in targets)
want = sorted([("TwakeChatTests", "container:TwakeChat.xcodeproj"),
               ("DesignSystemTests", "container:Packages/DesignSystem"),
               ("MatrixDataTests", "container:TwakeChat.xcodeproj"),
               # TWAK-65: the first feature package's tests run on the simulator (DesignSystem is iOS-only).
               ("AuthenticationTests", "container:Packages/Features/Authentication"),
               # TWAK-66: the chat list feature's tests, the same way.
               ("ChatListTests", "container:Packages/Features/ChatList")])
report(got == want, f"test plan lists exactly TwakeChatTests, DesignSystemTests, MatrixDataTests, AuthenticationTests, ChatListTests (got {got})")
report(not any(t["name"] in ("DomainTests", "AppSharedTests") for t in targets),
       "test plan leaves out DomainTests and AppSharedTests (they run on the host)")
app = [t for t in targets if t["name"] == "TwakeChatTests"]
report(bool(tests_id) and bool(app) and app[0]["identifier"] == tests_id,
       f"test plan's TwakeChatTests is the project's TwakeChatTests target ({tests_id})")
md = [t for t in targets if t["name"] == "MatrixDataTests"]
report(bool(matrix_id) and bool(md) and md[0]["identifier"] == matrix_id,
       f"test plan's MatrixDataTests is the project's MatrixDataTests target ({matrix_id})")
report(all(not t.get("skipped") for t in plan.get("testTargets", [])), "no test target in the plan is skipped")
sys.exit(1 if bad else 0)
PY
[ $? -eq 0 ] || FAILURES=$((FAILURES + 1))

check "the TwakeChat scheme's default test plan is TwakeChat.xctestplan" bash -c \
  "tr -d '\n' < '$SCHEME' | grep -qE '<TestPlanReference[[:space:]]+reference = \"container:TwakeChat.xctestplan\"[[:space:]]+default = \"YES\"'"
check "TwakeChatTests is hosted by the app, MatrixDataTests is not (Debug and Release: two TEST_HOST lines)" bash -c \
  "[ \$(grep -c 'TEST_HOST = \"\$(BUILT_PRODUCTS_DIR)/TwakeChat.app/' '$PBX') -eq 2 ]"
check "the project's test targets compile the synchronized Tests/TwakeChatTests and Tests/MatrixDataTests folders" \
  bash -c "grep -q 'path = Tests/TwakeChatTests;' '$PBX' && grep -q 'path = Tests/MatrixDataTests;' '$PBX'"
# The package products the MatrixDataTests native target depends on: MatrixData, plus Domain and AppShared whose types
# the mapper tests use directly (TWAK-64: once TwakeChatTests links MatrixData too, Xcode builds them as frameworks).
matrix_test_products() {
  awk 'index($0, "/* MatrixDataTests */ = {") { c = 1; next }
       c { c = 0; t = ($0 ~ /isa = PBXNativeTarget;/) }
       t && /packageProductDependencies = \(/ { p = 1; next }
       p && /\);/ { exit }
       p { print $3 }' "$PBX"
}
check "MatrixDataTests links MatrixData, Domain and AppShared only" test "$(matrix_test_products | sort | tr '\n' ' ')" = "AppShared Domain MatrixData "
# Constraints row 5: the test bundles inherit the project's Swift 6, strict concurrency, warnings-as-errors and
# iOS 18.0 settings. Their own build configurations must not set any of them.
test_target_settings() {
  awk '/isa = XCBuildConfiguration;/ { c = 1; s = ""; next }
       c && /TEST_HOST|BUNDLE_LOADER|PRODUCT_BUNDLE_IDENTIFIER = app\.twake\.ios\.chat\.tests/ { t = 1 }
       c { s = s "\n" $0 }
       c && /^\t\t\};/ { if (t) print s; c = 0; t = 0 }' "$PBX"
}
check "test bundles set none of SWIFT_VERSION, SWIFT_STRICT_CONCURRENCY, SWIFT_TREAT_WARNINGS_AS_ERRORS, IPHONEOS_DEPLOYMENT_TARGET" \
  bash -c "[ -n \"\$1\" ] && ! printf '%s' \"\$1\" | grep -qE 'SWIFT_VERSION|SWIFT_STRICT_CONCURRENCY|SWIFT_TREAT_WARNINGS_AS_ERRORS|IPHONEOS_DEPLOYMENT_TARGET'" \
  _ "$(test_target_settings)"

# ---------------------------------------------------------------- test files
# Every test target has at least one <TypeUnderTest>Tests.swift (naming.md), uses Swift Testing,
# and imports nothing but Testing, the module under test and what the app test needs (ADR 0010: no XCTest, no mocks).
# TWAK-63: Foundation is allowed everywhere (URL, Data, JSONEncoder), and TwakeChatTests may import AppShared for the
# hosted Keychain round trips, which need the app's entitlements.
allowed_test_imports() {
  case "$1" in
    # TWAK-64: hosted staging test. TWAK-65: the root restore tests use the Authentication flow and its fake.
    # TWAK-66: the root joins Authentication and ChatList, so its tests name both.
    TwakeChat) echo "Testing Foundation TwakeChat SwiftUI AppShared Domain MatrixData Authentication AuthenticationTestSupport ChatList" ;;
    MatrixData) echo "Testing Foundation MatrixData Domain AppShared" ;; # TWAK-64: mapper tests
    *) echo "Testing Foundation $1" ;;
  esac
}
for m in Domain AppShared MatrixData DesignSystem TwakeChat; do
  case "$m" in
    TwakeChat | MatrixData) dir="Tests/${m}Tests" ;; # targets of the Xcode project
    *) dir="Packages/$m/Tests/${m}Tests" ;;
  esac
  files="$(find "$dir" -name '*.swift' 2>/dev/null | sort)"
  if [ -z "$files" ]; then fail "${m}Tests: has a test file in $dir"; continue; fi
  pass "${m}Tests: has a test file in $dir"
  check "${m}Tests: every file is named <TypeUnderTest>Tests.swift" bash -c \
    "[ -z \"\$(find '$dir' -name '*.swift' ! -name '*Tests.swift')\" ]"
  check "${m}Tests: has at least one @Test with #expect" bash -c \
    "grep -qE '@Test' $(echo "$files" | tr '\n' ' ') && grep -qE '#expect' $(echo "$files" | tr '\n' ' ')"
  bad=""
  for imp in $(grep -hoE '^[[:space:]]*(@[A-Za-z_]+[[:space:]]+)*import[[:space:]]+([a-z]+[[:space:]]+)?[A-Za-z_][A-Za-z0-9_.]*' $files | awk '{print $NF}' | cut -d. -f1 | sort -u); do
    case " $(allowed_test_imports "$m") " in *" $imp "*) ;; *) bad="$bad $imp" ;; esac
  done
  if [ -z "$bad" ]; then pass "${m}Tests: imports only $(allowed_test_imports "$m")"; else fail "${m}Tests: imports not allowed:$bad"; fi
done
check "TwakeChatTests reaches the app with @testable import" grep -rq '^@testable import TwakeChat$' Tests/TwakeChatTests
# TWAK-64: MatrixDataTests may use @testable import MatrixData, for the internal mapper whose signatures name SDK types
# and so cannot be public (ADR 0006). It still never imports the SDK.
check "package tests use the public API (no @testable import)" bash -c \
  "! grep -rq '@testable' Packages/*/Tests"
check "MatrixDataTests uses @testable only for MatrixData" bash -c \
  "! grep -rh '@testable' Tests/MatrixDataTests | grep -vqx '@testable import MatrixData'"

# ---------------------------------------------------------------- no new dependency
# TWAK-48: the Matrix SDK, pinned exactly in MatrixData, is the only remote package (ADR 0003, ADR 0006).
# Any other remote package (a mocking library included, ADR 0010) still fails.
check "no remote package in any Package.swift other than MatrixData (no mocking library)" bash -c \
  "! grep -q '\.package(url:' \$(ls Packages/*/Package.swift | grep -v '^Packages/MatrixData/')"
check "MatrixData's only remote package is the Matrix SDK, exact 26.04.01 (no mocking library)" bash -c \
  "[ \"\$(grep -o '\.package(url:[^)]*)' Packages/MatrixData/Package.swift)\" = '.package(url: \"https://github.com/matrix-org/matrix-rust-components-swift\", exact: \"26.04.01\")' ]"
check "no remote package in the project (no mocking library)" bash -c "! grep -q XCRemoteSwiftPackageReference '$PBX'"

if [ "$FAILURES" -eq 0 ]; then echo "test harness: all checks passed"; exit 0; fi
echo "test harness: $FAILURES check(s) failed"; exit 1
