#!/bin/bash
# Tests scripts/check-architecture.sh (TWAK-36) on the trees in scripts/tests/architecture-fixtures/:
# `clean` must pass; each `ruleN-*` tree holds exactly one violation and must fail with exactly one
# "Rule N (ADR 000X)" line and no other rule's message. Then the same on edge-case trees it writes under $TMPDIR.
# Exits non-zero if any case fails.
set -uo pipefail

repo="$(cd "$(dirname "$0")/../.." && pwd)"
fixtures="$repo/scripts/tests/architecture-fixtures"

failures=0
cases=0

expect() {  # expect <case name> <description> <condition...>
  local name="$1" what="$2"; shift 2
  cases=$((cases + 1))
  if "$@"; then echo "ok   $name: $what"; else echo "FAIL $name: $what"; failures=$((failures + 1)); fi
}

adr_of() {
  case "$1" in
    1) echo 0006 ;;
    2) echo 0002 ;;
    3 | 4) echo 0005 ;;
    5) echo 0003 ;;
  esac
}

for dir in "$fixtures"/*/; do
  name="$(basename "$dir")"
  out="$(bash "$repo/scripts/check-architecture.sh" "$dir" 2>&1)"
  status=$?
  rule_lines="$(printf '%s\n' "$out" | grep -E '^Rule [0-9]+ \(ADR [0-9]{4}\): ' || true)"

  if [ "$name" = clean ]; then
    expect "$name" "exits 0" test "$status" -eq 0
    expect "$name" "reports no violation" test -z "$rule_lines"
    continue
  fi

  rule="${name#rule}"
  rule="${rule%%-*}"
  adr="$(adr_of "$rule")"
  expect "$name" "exits 1" test "$status" -eq 1
  expect "$name" "reports exactly one violation" test "$(printf '%s\n' "$rule_lines" | grep -c '^Rule ')" -eq 1
  expect "$name" "names rule $rule and ADR $adr" grep -q "^Rule $rule (ADR $adr): " <<< "$rule_lines"
  [ "$status" -eq 0 ] || printf '     %s\n' "$rule_lines"
done

# Edge cases on throwaway trees under $TMPDIR: import forms, the other packages of each rule, the other
# requirement forms of rule 5, skipped folders and error paths. Each `rule` case holds one violation.
work="$(mktemp -d "${TMPDIR:-/tmp}/check_architecture_test.XXXXXX")" || exit 1
trap 'rm -rf "$work"' EXIT

put() {  # put <case> <path> <content>: writes one file of a case's tree
  mkdir -p "$work/$1/$(dirname "$2")"
  printf '%s\n' "$3" > "$work/$1/$2"
}

run_tree() {  # run_tree <case>: sets $status, $out and $rule_lines
  out="$(bash "$repo/scripts/check-architecture.sh" "$work/$1" 2>&1)"
  status=$?
  rule_lines="$(printf '%s\n' "$out" | grep -E '^Rule [0-9]+ \(ADR [0-9]{4}\): ' || true)"
}

rule_case() {  # rule_case <case> <rule> <path> <content>: the tree must fail with only that rule, once
  local name="$1" rule="$2" adr
  adr="$(adr_of "$rule")"
  put "$name" "$3" "$4"
  run_tree "$name"
  expect "$name" "exits 1" test "$status" -eq 1
  expect "$name" "reports exactly one violation" test "$(printf '%s\n' "$rule_lines" | grep -c '^Rule ')" -eq 1
  expect "$name" "names rule $rule and ADR $adr" grep -q "^Rule $rule (ADR $adr): " <<< "$rule_lines"
}

clean_case() {  # clean_case <case>: the tree already written with put must pass
  run_tree "$1"
  expect "$1" "exits 0" test "$status" -eq 0
  expect "$1" "reports no violation" test -z "$rule_lines"
}

sdk_url="https://github.com/matrix-org/matrix-rust-components-swift"

# Rule 1: every import form, both SDK modules, files outside Packages and test targets.
rule_case edge-rule1-testable 1 Packages/Features/Chat/Tests/ChatTests/A.swift '@testable import MatrixRustSDK'
rule_case edge-rule1-exported 1 NotificationService/A.swift '@_exported import MatrixRustSDK'
rule_case edge-rule1-package-import 1 TwakeChat/A.swift 'package import MatrixRustSDK'
rule_case edge-rule1-internal-import 1 TwakeChat/A.swift '  internal import MatrixRustSDK'
rule_case edge-rule1-kind-import 1 TwakeChat/A.swift 'import class MatrixRustSDK.Client'
rule_case edge-rule1-ffi 1 Packages/Features/Chat/Sources/Chat/A.swift 'import struct MatrixSDKFFI.Foo'
rule_case edge-rule1-root-manifest 1 Package.swift ".package(url: \"$sdk_url\", exact: \"26.04.01\")"

# Rule 2: @available(iOS and #available in the app, in Domain and in MatrixData.
rule_case edge-rule2-attribute 2 Packages/Domain/Sources/Domain/A.swift '@available(iOS 26, *) struct A {}'
rule_case edge-rule2-app 2 TwakeChat/A.swift 'func f() { if #available(iOS 26, *) {} }'
rule_case edge-rule2-matrixdata 2 Packages/MatrixData/Sources/MatrixData/A.swift 'func f() { guard #available(iOS 26, *) else { return } }'

# Rule 3: every package's forbidden local dependencies.
rule_case edge-rule3-domain 3 Packages/Domain/Package.swift '.package(path: "../AppShared")'
rule_case edge-rule3-appshared 3 Packages/AppShared/Package.swift '.package(path: "../Domain")'
rule_case edge-rule3-designsystem 3 Packages/DesignSystem/Package.swift '.package(path: "../Domain")'
rule_case edge-rule3-matrixdata 3 Packages/MatrixData/Package.swift '.package(path: "../DesignSystem")'
rule_case edge-rule3-feature-on-matrixdata 3 Packages/Features/Chat/Package.swift '.package(path: "../../MatrixData")'
rule_case edge-rule3-feature-on-appshared 3 Packages/Features/Chat/Package.swift '.package(name: "AppShared", path: "../../AppShared")'
# A manifest may put `path:` on its own line; the dependency is the same.
rule_case edge-rule3-multiline 3 Packages/Features/Chat/Package.swift '.package(
  path: "../Login"
)'

# Rule 4: the other two checked packages, and an attribute before the import.
rule_case edge-rule4-appshared 4 Packages/AppShared/Sources/AppShared/A.swift 'import UIKit'
rule_case edge-rule4-designsystem 4 Packages/DesignSystem/Sources/DesignSystem/A.swift 'import UIKit'
rule_case edge-rule4-attribute 4 Packages/Domain/Sources/Domain/A.swift '@preconcurrency import Combine'

# Rule 5: every requirement form other than exact:.
for form in 'branch: "main"' 'revision: "2916f3f9"' '"26.04.01"..<"27.0.0"' '"26.04.01"..."26.04.01"' \
  '.upToNextMajor(from: "26.04.01")' '.upToNextMinor(from: "26.04.01")'; do
  rule_case "edge-rule5-$(printf '%s' "$form" | tr -c 'A-Za-z0-9' '-')" 5 Packages/MatrixData/Package.swift \
    ".package(
  url: \"$sdk_url\",
  $form
)"
done

# Build output and the fixture trees are skipped; MatrixData may import the SDK; DesignSystem tests may check versions.
for skipped in .build/checkouts/x .swiftpm/x DerivedData/x SourcePackages/x scripts/tests/architecture-fixtures/x; do
  put edge-skipped "$skipped/TwakeChat/A.swift" '@preconcurrency import MatrixRustSDK
func f() { if #available(iOS 26, *) {} }'
  put edge-skipped "$skipped/Package.swift" ".package(url: \"$sdk_url\", from: \"1.0.0\")"
done
put edge-skipped Packages/MatrixData/Sources/MatrixData/A.swift '@_exported import MatrixRustSDK'
put edge-skipped Packages/DesignSystem/Tests/DesignSystemTests/A.swift 'func f() { if #available(iOS 26, *) {} }'
clean_case edge-skipped

# Every violation is reported before the check exits, with a count.
put edge-all-reported TwakeChat/A.swift 'import MatrixRustSDK'
put edge-all-reported Packages/Domain/Sources/Domain/A.swift 'import SwiftUI'
put edge-all-reported Packages/Features/Chat/Sources/Chat/A.swift 'func f() { if #available(iOS 26, *) {} }'
run_tree edge-all-reported
expect edge-all-reported "exits 1" test "$status" -eq 1
expect edge-all-reported "reports rules 1, 4 and 2" \
  test "$(printf '%s\n' "$rule_lines" | cut -d' ' -f2 | sort | tr '\n' ' ')" = "1 2 4 "
expect edge-all-reported "prints the count" grep -q 'failed: 3 violation(s)' <<< "$out"

# A ROOT that does not exist is an error, never a pass.
out="$(bash "$repo/scripts/check-architecture.sh" "$work/does-not-exist" 2>&1)"
status=$?
expect edge-missing-root "exits non-zero" test "$status" -ne 0
expect edge-missing-root "does not say it passed" bash -c '! grep -q passed <<< "$1"' _ "$out"

# More import forms: SPI and implementation-only imports, an access level on a forbidden import, a file name
# with a space.
rule_case edge-rule1-spi 1 TwakeChat/A.swift '@_spi(Experimental) import MatrixRustSDK'
rule_case edge-rule1-implementation-only 1 NotificationService/A.swift '@_implementationOnly import MatrixRustSDK'
rule_case edge-rule1-space-in-name 1 'TwakeChat/My Session.swift' 'import MatrixRustSDK'
rule_case edge-rule4-public-import 4 Packages/Domain/Sources/Domain/A.swift 'public import SwiftUI'

# Rule 2 (ADR 0002: "no @available for iOS versions"): the iOS version may come after another platform
# or be given as a label. Domain and AppShared declare macOS too, so the multi-platform form is the likely one.
rule_case edge-rule2-introduced 2 Packages/Features/Chat/Sources/Chat/A.swift '@available(iOS, introduced: 18.0) struct A {}'
rule_case edge-rule2-multi-platform 2 Packages/Domain/Sources/Domain/A.swift '@available(macOS 15, iOS 18, *) struct A {}'

# The line format is "Rule N (ADR 000X): <path relative to ROOT>:<line>: ...", and two violations in one file
# are both reported, each with its own line.
put edge-format Packages/Domain/Sources/Domain/A.swift 'import Foundation
import SwiftUI
import UIKit'
run_tree edge-format
expect edge-format "exits 1" test "$status" -eq 1
expect edge-format "names the relative path and line 2" \
  grep -q '^Rule 4 (ADR 0005): Packages/Domain/Sources/Domain/A.swift:2: .*SwiftUI' <<< "$rule_lines"
expect edge-format "names the relative path and line 3" \
  grep -q '^Rule 4 (ADR 0005): Packages/Domain/Sources/Domain/A.swift:3: .*UIKit' <<< "$rule_lines"
expect edge-format "reports exactly two violations" test "$(printf '%s\n' "$rule_lines" | grep -c '^Rule ')" -eq 2

# Allowed forms pass: a trailing slash on an allowed path, a commented-out dependency, a submodule of an
# allowed module, and a second remote package next to the exact SDK pin (only the SDK's pin is judged).
put edge-allowed Packages/Features/Chat/Package.swift '.package(path: "../../Domain/"),
.package(path: "./../../DesignSystem")'
put edge-allowed Packages/Domain/Package.swift '// .package(path: "../AppShared"),'
put edge-allowed Packages/Domain/Sources/Domain/A.swift 'import Foundation.NSString'
put edge-allowed Packages/MatrixData/Package.swift ".package(path: \"../Domain\"),
.package(url: \"https://example.com/other.git\", from: \"1.0.0\"),
.package(url: \"$sdk_url\", exact: \"26.04.01\")"
clean_case edge-allowed

# With no ROOT the check scans the repository it lives in, wherever it is started from.
out="$(cd "$work" && bash "$repo/scripts/check-architecture.sh" 2>&1)"
status=$?
expect edge-default-root "exits 0 on the repository" test "$status" -eq 0
expect edge-default-root "says it passed" grep -q '^Architecture check passed' <<< "$out"

# Tester cases (TWAK-36). Rule 2 as the card words it: "`@available(iOS` appears outside Packages/DesignSystem".
# The Notification Service Extension is an iOS app extension, so an iOSApplicationExtension check is an iOS
# version check too; a space before the parenthesis does not hide it either.
rule_case edge-rule2-app-extension 2 NotificationService/A.swift '@available(iOSApplicationExtension 26, *) struct A {}'
rule_case edge-rule2-space 2 TwakeChat/A.swift '@available (iOS 26, *) struct A {}'
# A check for another platform only is not an iOS version check: Domain and AppShared also build for macOS.
put edge-other-platform Packages/Domain/Sources/Domain/A.swift '@available(macOS 15, *) struct A {}'
put edge-other-platform Packages/AppShared/Sources/AppShared/A.swift '@available(*, unavailable) struct A {}'
clean_case edge-other-platform
# A ROOT whose path holds a space is scanned, not split.
rule_case 'edge root with space' 1 TwakeChat/A.swift 'import MatrixRustSDK'

# #unavailable is the same iOS version check as #available, inverted (Swift 5.6+). ADR 0002 and the constraints
# row ban iOS version checks outside DesignSystem, and TWAK-34's acceptance scan bans '#(un)?available' too.
rule_case edge-rule2-unavailable 2 Packages/Features/Chat/Sources/Chat/A.swift 'func f() { if #unavailable(iOS 26) {} }'
# Rule 4 as the card words it for DesignSystem: "DesignSystem only SwiftUI", so Foundation is not allowed there.
rule_case edge-rule4-designsystem-foundation 4 Packages/DesignSystem/Sources/DesignSystem/A.swift 'import Foundation'
# Rule 3: MatrixData may not depend on a feature either.
rule_case edge-rule3-matrixdata-on-feature 3 Packages/MatrixData/Package.swift '.package(path: "../Features/Chat")'
# Build output inside a package, where `swift test` and SwiftPM really put it: Packages/<P>/.build holds the SDK
# checkout (its own Package.swift, @available) and the generated test entry point (@available).
put edge-nested-build Packages/MatrixData/.build/checkouts/matrix-rust-components-swift/Package.swift \
  "@available(iOS 16, *)
let p = 1
.package(url: \"$sdk_url\", from: \"1.0.0\")"
put edge-nested-build Packages/MatrixData/.build/checkouts/matrix-rust-components-swift/Sources/A.swift \
  'import MatrixRustSDK
@available(iOS 16, *) struct A {}'
put edge-nested-build Packages/Domain/.build/debug/runner.swift '@available(macOS 15, iOS 18, *) @main struct Runner {}'
put edge-nested-build Packages/Features/Chat/.swiftpm/x/A.swift 'import MatrixRustSDK'
clean_case edge-nested-build

# Tester cases (TWAK-36 QA).
# Rule 1: a manifest that names the SDK only in a target's .product(...) still declares a dependency on it.
rule_case tester-rule1-product-only 1 Packages/Features/Chat/Package.swift \
  '.target(name: "Chat", dependencies: [.product(name: "MatrixRustSDK", package: "matrix-rust-components-swift")])'
# Rule 1: a package whose folder only starts with "MatrixData" is outside MatrixData.
rule_case tester-rule1-sibling-name 1 Packages/MatrixDataExtras/Package.swift \
  ".package(url: \"$sdk_url\", exact: \"26.04.01\")"
# Rules 1 and 4: Swift accepts two imports on one line separated by ';'; the second one is an import too.
rule_case tester-rule1-semicolon 1 TwakeChat/A.swift 'import Foundation; import MatrixRustSDK'
rule_case tester-rule4-semicolon 4 Packages/Domain/Sources/Domain/A.swift 'import Foundation; import SwiftUI'
# Rule 3: what a path points at decides, not its last component: Packages/Features/Domain is a feature.
rule_case tester-rule3-matrixdata-on-feature-named-domain 3 Packages/MatrixData/Package.swift \
  '.package(path: "../Features/Domain")'
# Rule 3 does not judge remote packages: DesignSystem needs a snapshot library (ADR 0010).
put tester-designsystem-snapshot Packages/DesignSystem/Package.swift \
  '.package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.17.0")'
clean_case tester-designsystem-snapshot

# Tester cases (TWAK-36 QA, round 2).
# Rule 3: a feature on a feature is named as such, not as a generic "may depend only on" break.
out="$(bash "$repo/scripts/check-architecture.sh" "$fixtures/rule3-feature-depends-on-feature" 2>&1)"
expect tester-rule3-feature-message "says a feature must not depend on another feature" \
  grep -q '^Rule 3 (ADR 0005): Packages/Features/Chat/Package.swift:[0-9]*: .*feature Features/Chat depends on feature Features/Login' <<< "$out"
# Rule 2: swift-format (lineLength 100) wraps a long attribute, putting iOS on the next line. It is still an
# iOS version check outside DesignSystem.
rule_case tester-rule2-wrapped-attribute 2 Packages/Features/Chat/Sources/Chat/A.swift '@available(
  iOS, deprecated: 26.0,
  message: "Use the Design System glass background modifier instead of this legacy one here"
)
struct A {}'

# Tester cases (TWAK-36 QA, round 3).
# Rule 2: only Packages/DesignSystem itself is exempt, not a package whose name starts with it nor a feature
# called DesignSystem.
rule_case tester-rule2-designsystem-prefix 2 Packages/DesignSystemKit/Sources/DesignSystemKit/A.swift \
  'func f() { if #available(iOS 26, *) {} }'
rule_case tester-rule2-feature-named-designsystem 2 Packages/Features/DesignSystem/Sources/DesignSystem/A.swift \
  '@available(iOS 26, *) struct A {}'
# Rule 4: a source file in a subfolder of a target is a source file too.
rule_case tester-rule4-nested-folder 4 Packages/Domain/Sources/Domain/Models/Room/A.swift 'import SwiftUI'
# Rule 4 checks only Domain, AppShared and DesignSystem (the card's list): MatrixData sources, feature sources and
# MatrixData tests are not judged on system imports, and MatrixData tests may import the SDK (rule 1).
put tester-unchecked-imports Packages/MatrixData/Sources/MatrixData/A.swift 'import Foundation
import OSLog'
put tester-unchecked-imports Packages/Features/Chat/Sources/Chat/A.swift 'import Observation
import SwiftUI'
put tester-unchecked-imports Packages/MatrixData/Tests/MatrixDataTests/A.swift 'import Testing
import MatrixRustSDK
@testable import MatrixData'
clean_case tester-unchecked-imports
# Rule 5: the SDK URL with a .git suffix is the same package: exact: passes, from: fails.
put tester-sdk-git-suffix Packages/MatrixData/Package.swift \
  ".package(url: \"$sdk_url.git\", exact: \"26.04.01\")"
clean_case tester-sdk-git-suffix
rule_case tester-rule5-git-suffix 5 Packages/MatrixData/Package.swift \
  ".package(url: \"$sdk_url.git\", from: \"26.04.01\")"
# A feature that declares the SDK with from: breaks rules 1 and 5 on the same line; both are reported.
put tester-rule1-and-5 Packages/Features/Chat/Package.swift ".package(url: \"$sdk_url\", from: \"26.04.01\")"
run_tree tester-rule1-and-5
expect tester-rule1-and-5 "exits 1" test "$status" -eq 1
expect tester-rule1-and-5 "reports rules 1 and 5, once each" \
  test "$(printf '%s\n' "$rule_lines" | cut -d' ' -f2 | sort | tr '\n' ' ')" = "1 5 "

# Tester cases (TWAK-36 issues, round 5).
# Rule 2: every @available on a line is judged, not only the first one.
rule_case tester-rule2-second-attribute-platform 2 Packages/Domain/Sources/Domain/A.swift \
  '@available(macOS 15, *) @available(iOS 18, *) struct A {}'
rule_case tester-rule2-second-attribute-deprecated 2 Packages/Domain/Sources/Domain/A.swift \
  '@available(*, deprecated) @available(iOS 18, *) struct A {}'
# Rule 2: a line comment that ends in "@available" does not hide the attribute on the next line, which is the
# line reported.
rule_case tester-rule2-after-comment 2 Packages/Domain/Sources/Domain/A.swift '// see @available
@available(iOS 18, *) struct A {}'
expect tester-rule2-after-comment "reports line 2" grep -q '^Rule 2 (ADR 0002): Packages/Domain/Sources/Domain/A.swift:2: ' <<< "$rule_lines"
# Rule 2: an @available(iOS in a comment is not code.
put tester-rule2-comment-only Packages/Domain/Sources/Domain/A.swift '// no @available(iOS 18, *) here
/* nor @available(iOS 26, *) here */
struct A {}'
clean_case tester-rule2-comment-only

# Tester cases (TWAK-36 tester, round 6).
# Rule 5: a manifest may keep the SDK URL in a constant; the .package(...) call then does not spell the package name,
# but it still declares the SDK, so from: must fail. (Outside MatrixData, rule 1 already fails on the constant's line.)
rule_case tester-rule5-url-constant 5 Packages/MatrixData/Package.swift "let sdkURL = \"$sdk_url\"
let package = Package(
  name: \"MatrixData\",
  dependencies: [
    .package(url: sdkURL, from: \"26.04.01\")
  ]
)"
# The same manifest with exact: passes.
put tester-sdk-url-constant-exact Packages/MatrixData/Package.swift "let sdkURL = \"$sdk_url\"
let package = Package(name: \"MatrixData\", dependencies: [.package(url: sdkURL, exact: \"26.04.01\")])"
clean_case tester-sdk-url-constant-exact

# Tester cases (TWAK-36 tester, round 7).
# Module names match whole, never by prefix: a module that only starts with an allowed name is not allowed (rule 4),
# and a module that only starts with an SDK module name is not the SDK (rule 1).
rule_case tester-rule4-prefix-of-allowed 4 Packages/Domain/Sources/Domain/A.swift 'import FoundationNetworking'
rule_case tester-rule4-prefix-of-allowed-appshared 4 Packages/AppShared/Sources/AppShared/A.swift 'import SecurityInterface'
put tester-sdk-prefix TwakeChat/A.swift 'import MatrixRustSDKExtras
import MatrixSDKFFIHelpers'
clean_case tester-sdk-prefix
# A file saved with CRLF line endings and a tab between `import` and the module is still read.
rule_case tester-rule1-crlf 1 TwakeChat/A.swift "$(printf 'import Foundation\r\nimport MatrixRustSDK\r')"
rule_case tester-rule4-crlf 4 Packages/Domain/Sources/Domain/A.swift "$(printf 'import Foundation\r\nimport SwiftUI\r')"
rule_case tester-rule4-tab 4 Packages/Domain/Sources/Domain/A.swift "$(printf '\timport\tSwiftUI')"
rule_case tester-rule2-crlf 2 Packages/Features/Chat/Sources/Chat/A.swift \
  "$(printf 'func f() {\r\n  if #available(iOS 26, *) {}\r\n}\r')"
rule_case tester-rule5-crlf 5 Packages/MatrixData/Package.swift \
  "$(printf '.package(\r\n  url: "%s",\r\n  from: "26.04.01"\r\n)\r' "$sdk_url")"

echo "$((cases - failures))/$cases passed"
[ "$cases" -gt 0 ] && [ "$failures" -eq 0 ]
