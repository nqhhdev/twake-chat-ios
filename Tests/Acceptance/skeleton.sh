#!/usr/bin/env bash
# Acceptance checks for TWAK-34 (Xcode app skeleton with the core layer packages).
#
# Usage, from the repository root:
#   Tests/Acceptance/skeleton.sh static    # text checks only: package graph, imports, settings, scheme, .gitignore
#   Tests/Acceptance/skeleton.sh compile   # static + compile every module and the app with swiftc (no SwiftPM, no simulator)
#   Tests/Acceptance/skeleton.sh full      # static + the card's real commands: swift build, SwiftPM negative tests,
#                                          # xcodebuild on an iOS 26 simulator (default)
#
# Owner decision 2026-11-12: the app targets iOS 26 only; there is no iOS 18 runtime, build or launch check.
#
# The simulator destination can be overridden:
#   IOS26_DEST='platform=iOS Simulator,OS=26.2,name=iPhone 17'
set -uo pipefail

MODE="${1:-full}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/twak34-acceptance.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

FAILURES=0
pass() { printf 'ok   %s\n' "$1"; }
fail() { printf 'FAIL %s\n' "$1"; FAILURES=$((FAILURES + 1)); }
check() { local name="$1"; shift; if "$@" >/dev/null 2>&1; then pass "$name"; else fail "$name"; fi; }

PACKAGES=(Domain AppShared DesignSystem MatrixData)
PBX=TwakeChat.xcodeproj/project.pbxproj

# ---------------------------------------------------------------- static
# ADR 0005 dependency table: the local packages each Package.swift may depend on.
expected_deps() {
  case "$1" in
    MatrixData) echo "AppShared Domain" ;;
    *) echo "" ;;
  esac
}
# ADR 0005 allowed imports, exactly as its table lists them.
allowed_imports() {
  case "$1" in
    Domain) echo "Foundation" ;;
    AppShared) echo "Foundation Security OSLog" ;;
    DesignSystem) echo "SwiftUI" ;;
    MatrixData) echo "Domain AppShared" ;; # the Matrix SDK is added by card e
  esac
}
platforms_of() { grep -oE '\.(iOS|macOS|tvOS|watchOS|visionOS)\(\.v[0-9_]+\)' "Packages/$1/Package.swift" | sort | tr '\n' ' ' | sed 's/ $//'; }

for p in "${PACKAGES[@]}"; do
  m="Packages/$p/Package.swift"
  if [ ! -f "$m" ]; then fail "$p: Package.swift exists"; continue; fi
  check "$p: swift-tools-version 6.2 (Swift 6 mode, complete concurrency)" grep -qE '^// swift-tools-version: ?6\.2' "$m"
  check "$p: warnings are errors" grep -q '\.treatAllWarnings(as: \.error)' "$m"
  check "$p: no unsafeFlags" bash -c "! grep -q unsafeFlags '$m'"
  check "$p: no remote package dependency" bash -c "! grep -q '\.package(url:' '$m'"
  actual="$(grep -oE '\.package\(path: "\.\./[A-Za-z]+"\)' "$m" | sed -E 's/.*\.\.\/([A-Za-z]+).*/\1/' | sort | tr '\n' ' ' | sed 's/ $//')"
  if [ "$actual" = "$(expected_deps "$p")" ]; then pass "$p: package dependencies match ADR 0005 ('$actual')"
  else fail "$p: package dependencies '$actual', ADR 0005 expects '$(expected_deps "$p")'"; fi
  n_sources=$(find "Packages/$p/Sources/$p" -name '*.swift' | wc -l | tr -d ' ')
  check "$p: has a source file ($n_sources)" test "$n_sources" -ge 1
  bad=""
  for imp in $(grep -hoE '^[[:space:]]*(@[A-Za-z_]+[[:space:]]+)*import[[:space:]]+([a-z]+[[:space:]]+)?[A-Za-z_][A-Za-z0-9_.]*' -r "Packages/$p/Sources" | awk '{print $NF}' | cut -d. -f1 | sort -u); do
    case " $(allowed_imports "$p") " in *" $imp "*) ;; *) bad="$bad $imp" ;; esac
  done
  if [ -z "$bad" ]; then pass "$p: imports only what ADR 0005 allows"; else fail "$p: imports not allowed by ADR 0005:$bad"; fi
done

check "MatrixData target depends on the Domain and AppShared products only" bash -c '
  [ "$(grep -oE "\.product\(name: \"[A-Za-z]+\"" Packages/MatrixData/Package.swift | sort | tr "\n" " ")" = ".product(name: \"AppShared\" .product(name: \"Domain\" " ]'

[ "$(platforms_of Domain)" = ".iOS(.v18) .macOS(.v15)" ] && pass "Domain: iOS 18 and macOS 15" || fail "Domain platforms: $(platforms_of Domain)"
[ "$(platforms_of AppShared)" = ".iOS(.v18) .macOS(.v15)" ] && pass "AppShared: iOS 18 and macOS 15" || fail "AppShared platforms: $(platforms_of AppShared)"
[ "$(platforms_of DesignSystem)" = ".iOS(.v18)" ] && pass "DesignSystem: iOS 18 only" || fail "DesignSystem platforms: $(platforms_of DesignSystem)"
[ "$(platforms_of MatrixData)" = ".iOS(.v18)" ] && pass "MatrixData: iOS 18 only" || fail "MatrixData platforms: $(platforms_of MatrixData)"

check "no Matrix SDK import anywhere" bash -c "! grep -rnE --include='*.swift' 'import[[:space:]]+(MatrixRustSDK|MatrixRustComponents|MatrixSDK|MatrixSDKCrypto)' TwakeChat Packages"
check "no #available or @available anywhere" bash -c "! grep -rnE --include='*.swift' '#available|#unavailable|@available' TwakeChat Packages"
check "no Features package (ADR 0011: created with its first feature)" test ! -e Packages/Features

# App target
check "entry point TwakeChat/TwakeChatApp.swift is @main and shows RootView" bash -c \
  "grep -q '^@main' TwakeChat/TwakeChatApp.swift && grep -q 'RootView()' TwakeChat/TwakeChatApp.swift"
check "root view has no screen content" bash -c "! grep -qE '\b(Text|Image|Button|Label|List|NavigationStack)\(' TwakeChat/RootView.swift"
check "project file exists" test -f "$PBX"
only_value() { # every occurrence of setting $1 has value $2, and there is at least one
  local values; values="$(grep -E "^[[:space:]]*$1 = " "$PBX" | sed -E "s/^[[:space:]]*$1 = \"?([^\";]*)\"?;.*/\1/" | sort -u)"
  [ "$values" = "$2" ]
}
check "PRODUCT_BUNDLE_IDENTIFIER is app.twake.ios.chat (ADR 0012)" only_value PRODUCT_BUNDLE_IDENTIFIER app.twake.ios.chat
# ADR 0012: version and build numbers above the Flutter app's last release, 2.26.1 (2330) in its pubspec.yaml.
above_flutter_release() {
  local mv bn; mv="$(grep -E '^[[:space:]]*MARKETING_VERSION = ' "$PBX" | sed -E 's/.*= "?([^";]*)"?;.*/\1/' | sort -u)"
  bn="$(grep -E '^[[:space:]]*CURRENT_PROJECT_VERSION = ' "$PBX" | sed -E 's/.*= "?([^";]*)"?;.*/\1/' | sort -u)"
  [ "$(printf '%s\n' "$mv" | wc -l)" -eq 1 ] && [ "$(printf '%s\n' "$bn" | wc -l)" -eq 1 ] || return 1
  [ "$bn" -gt 2330 ] || return 1
  [ "$(printf '2.26.1\n%s\n' "$mv" | sort -t. -k1,1n -k2,2n -k3,3n | tail -1)" = "$mv" ] && [ "$mv" != "2.26.1" ]
}
check "MARKETING_VERSION and CURRENT_PROJECT_VERSION exceed the Flutter app's 2.26.1 (2330) (ADR 0012)" above_flutter_release
check "IPHONEOS_DEPLOYMENT_TARGET is 18.0 (ADR 0002)" only_value IPHONEOS_DEPLOYMENT_TARGET 18.0
check "SDKROOT is iphoneos" only_value SDKROOT iphoneos
check "SWIFT_VERSION is 6.0" only_value SWIFT_VERSION 6.0
check "SWIFT_STRICT_CONCURRENCY is complete" only_value SWIFT_STRICT_CONCURRENCY complete
check "SWIFT_TREAT_WARNINGS_AS_ERRORS is YES" only_value SWIFT_TREAT_WARNINGS_AS_ERRORS YES
check "GCC_TREAT_WARNINGS_AS_ERRORS is YES" only_value GCC_TREAT_WARNINGS_AS_ERRORS YES
check "settings are in both Debug and Release project configurations" bash -c \
  "[ \$(grep -c 'SWIFT_TREAT_WARNINGS_AS_ERRORS = YES' '$PBX') -ge 2 ] && [ \$(grep -c 'IPHONEOS_DEPLOYMENT_TARGET = 18.0' '$PBX') -ge 2 ] && [ \$(grep -c 'SWIFT_VERSION = 6.0' '$PBX') -ge 2 ]"
check "no development team, entitlements or extension target (out of scope)" bash -c \
  "! grep -qE 'DEVELOPMENT_TEAM|CODE_SIGN_ENTITLEMENTS|app-extension' '$PBX'"
check "exactly one native target" bash -c "[ \$(grep -c 'isa = PBXNativeTarget' '$PBX') -eq 1 ]"
for p in "${PACKAGES[@]}"; do
  check "project references local package Packages/$p" grep -q "relativePath = Packages/$p;" "$PBX"
  check "TwakeChat target links $p" bash -c "awk '/packageProductDependencies = \(/,/\);/' '$PBX' | grep -q '/\* $p \*/'"
done
SCHEME=TwakeChat.xcodeproj/xcshareddata/xcschemes/TwakeChat.xcscheme
check "shared scheme TwakeChat exists and builds the TwakeChat target" bash -c \
  "grep -q 'BlueprintName = \"TwakeChat\"' '$SCHEME' && grep -q 'BuildableName = \"TwakeChat.app\"' '$SCHEME'"

# .gitignore
for path in build/x DerivedData/x Packages/Domain/.build/x Packages/Domain/.swiftpm/x \
            TwakeChat.xcodeproj/xcuserdata/me.xcuserdatad/x TwakeChat.xcodeproj/project.xcworkspace/xcuserdata/me.xcuserdatad/UserInterfaceState.xcuserstate .DS_Store; do
  check ".gitignore ignores $path" git check-ignore -q --no-index "$path"
done
for path in Package.resolved TwakeChat.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved \
            Packages/MatrixData/Package.resolved "$SCHEME" "$PBX" TwakeChat/TwakeChatApp.swift Packages/Domain/Package.swift; do
  check ".gitignore keeps $path" bash -c "! git check-ignore -q --no-index '$path'"
done

# Knowledge base: the Build page holds the real commands, the bundle checks clean, the log records the change.
BUILD_PAGE=.okf/workflows/build.md
check "okf.py --check passes" bash -c "python3 .okf/tools/okf.py --check | grep -q '^ok'"
check "Build page is no longer marked not runnable" bash -c "! grep -qi 'not runnable yet' '$BUILD_PAGE'"
check "Build page lists xcodebuild for the TwakeChat scheme on an iOS 26 simulator" bash -c \
  "grep -qE 'xcodebuild build .*-scheme TwakeChat .*OS=26' '$BUILD_PAGE'"
# Owner decision 2026-11-12: no iOS 18 runtime and no iOS 18 build check, so the Build page must not ask for either.
check "Build page has no iOS 18 build command (owner decision 2026-11-12)" bash -c \
  "! grep -qE 'OS=18|Build the app, iOS 18' '$BUILD_PAGE'"
check "Build page does not require an iOS 18 simulator runtime (owner decision 2026-11-12)" bash -c \
  "! grep -qiE 'iOS 18 simulator runtime' '$BUILD_PAGE'"
check "Build page lists swift build for Domain and AppShared" bash -c \
  "grep -q 'swift build' '$BUILD_PAGE' && grep -q 'Packages/Domain' '$BUILD_PAGE' && grep -q 'Packages/AppShared' '$BUILD_PAGE'"
check "log.md has a line for TWAK-34" grep -q 'TWAK-34' .okf/log.md

# ---------------------------------------------------------------- compile (swiftc only)
SWIFT_FLAGS=(-swift-version 6 -strict-concurrency=complete -warnings-as-errors -parse-as-library -module-cache-path "$WORK/module-cache")
compile_module() { # $1 module, $2 target triple, $3 sdk, $4.. dependency modules (only these are visible)
  local mod="$1" triple="$2" sdk="$3"; shift 3
  local out="$WORK/$triple/$mod"; mkdir -p "$out"
  local inc=(); for d in "$@"; do inc+=(-I "$WORK/$triple/$d" -L "$WORK/$triple/$d" -l"$d"); done
  xcrun swiftc "${SWIFT_FLAGS[@]}" -target "$triple" -sdk "$sdk" -module-name "$mod" \
    -emit-library -static -emit-module -emit-module-path "$out/$mod.swiftmodule" -o "$out/lib$mod.a" \
    ${inc[@]+"${inc[@]}"} $(find "Packages/$mod/Sources/$mod" -name '*.swift')
}
if [ "$MODE" = compile ]; then
  IOS_SDK="$(xcrun --sdk iphonesimulator --show-sdk-path)"
  MAC_SDK="$(xcrun --sdk macosx --show-sdk-path)"
  for triple in arm64-apple-ios26.0-simulator; do
    check "swiftc $triple: Domain" compile_module Domain "$triple" "$IOS_SDK"
    check "swiftc $triple: AppShared" compile_module AppShared "$triple" "$IOS_SDK"
    check "swiftc $triple: DesignSystem" compile_module DesignSystem "$triple" "$IOS_SDK"
    check "swiftc $triple: MatrixData with only Domain and AppShared visible" compile_module MatrixData "$triple" "$IOS_SDK" Domain AppShared
    inc=(); for d in "${PACKAGES[@]}"; do inc+=(-I "$WORK/$triple/$d" -L "$WORK/$triple/$d" -l"$d"); done
    check "swiftc $triple: app links all four modules" xcrun swiftc "${SWIFT_FLAGS[@]}" -target "$triple" -sdk "$IOS_SDK" \
      -module-name TwakeChat "${inc[@]}" TwakeChat/*.swift -o "$WORK/$triple/TwakeChat"
  done
  check "swiftc macOS 15: Domain" compile_module Domain arm64-apple-macosx15.0 "$MAC_SDK"
  check "swiftc macOS 15: AppShared" compile_module AppShared arm64-apple-macosx15.0 "$MAC_SDK"
fi

# ---------------------------------------------------------------- full (the card's commands)
if [ "$MODE" = full ]; then
  for p in Domain AppShared; do
    check "swift build in Packages/$p (host)" swift build --package-path "Packages/$p" --scratch-path "$WORK/host-$p"
  done
  IOS_SDK="$(xcrun --sdk iphonesimulator --show-sdk-path)"
  for p in "${PACKAGES[@]}"; do
    check "swift build Packages/$p for arm64-apple-ios26.0-simulator" swift build --package-path "Packages/$p" \
      --scratch-path "$WORK/ios-$p" --triple arm64-apple-ios26.0-simulator --sdk "$IOS_SDK"
  done

  # Error path: a warning must fail the package build.
  cp -R Packages "$WORK/neg-warn"; rm -rf "$WORK"/neg-warn/*/.build
  printf 'func twak34Warning() { var unused = 1; _ = unused }\n' > "$WORK/neg-warn/Domain/Sources/Domain/Warning.swift"
  # It must fail because of the warning itself (reported as an error), not for an unrelated reason.
  check "a warning in Domain fails swift build" bash -c \
    "! swift build --package-path '$WORK/neg-warn/Domain' >'$WORK/neg-warn.log' 2>&1 \
     && grep -qE 'Warning\.swift:[0-9]+:[0-9]+: error: .*never mutated' '$WORK/neg-warn.log'"
  # Error path: a layer violation must not compile. Each violation gets its own fresh copy of the packages, and the
  # build must fail on that file with "no such module", so one violation cannot make another check pass.
  layer_violation_fails() { # $1 package, $2 module it must not see, $3.. extra swift build arguments
    local pkg="$1" mod="$2"; shift 2
    local dir="$WORK/neg-layer-$pkg-$mod"
    cp -R Packages "$dir"; rm -rf "${dir:?}"/*/.build
    printf 'import %s\n' "$mod" > "$dir/$pkg/Sources/$pkg/Violation.swift"
    ! swift build --package-path "$dir/$pkg" "$@" >"$dir.log" 2>&1 \
      && grep -qE "$pkg/Violation\.swift:[0-9]+:[0-9]+: error: no such module '$mod'" "$dir.log"
  }
  IOS_ARGS=(--triple arm64-apple-ios26.0-simulator --sdk "$IOS_SDK")
  check "Domain importing AppShared fails swift build" layer_violation_fails Domain AppShared
  check "AppShared importing Domain fails swift build" layer_violation_fails AppShared Domain
  check "DesignSystem importing Domain fails swift build" layer_violation_fails DesignSystem Domain "${IOS_ARGS[@]}"
  # MatrixData's ADR 0005 row allows Domain and AppShared only.
  check "MatrixData importing DesignSystem fails swift build" layer_violation_fails MatrixData DesignSystem "${IOS_ARGS[@]}"

  # Error path: a warning in the app target must fail xcodebuild (SWIFT_TREAT_WARNINGS_AS_ERRORS takes effect).
  # The TwakeChat folder is a synchronized group, so a new file in a copy of the project joins the target.
  mkdir -p "$WORK/neg-app"
  cp -R TwakeChat TwakeChat.xcodeproj Packages "$WORK/neg-app/"; rm -rf "$WORK"/neg-app/Packages/*/.build
  printf 'func twak34AppWarning() { var unused = 1; _ = unused }\n' > "$WORK/neg-app/TwakeChat/Warning.swift"
  # It must fail because of the warning itself (reported as an error), not for an unrelated reason.
  check "a warning in the app target fails xcodebuild" bash -c \
    "cd '$WORK/neg-app' && ! xcodebuild build -project TwakeChat.xcodeproj -scheme TwakeChat \
       -destination 'generic/platform=iOS Simulator' -derivedDataPath '$WORK/dd-neg-app' >'$WORK/neg-app.log' 2>&1 \
     && grep -qE 'Warning\.swift:[0-9]+:[0-9]+: error: .*never mutated' '$WORK/neg-app.log'"

  xcode_build() { # $1 label, $2 destination
    local log="$WORK/xcodebuild-$1.log"
    xcodebuild build -project TwakeChat.xcodeproj -scheme TwakeChat -destination "$2" \
      -derivedDataPath "$WORK/dd-$1" >"$log" 2>&1
    local status=$?
    if [ $status -eq 0 ] && grep -q '\*\* BUILD SUCCEEDED \*\*' "$log" && ! grep -q 'warning:' "$log"; then return 0; fi
    grep -E 'warning:|error:' "$log" | sort -u | head -20 >&2; return 1
  }
  for spec in "ios26|${IOS26_DEST:-platform=iOS Simulator,OS=26.2,name=iPhone 17}"; do
    label="${spec%%|*}"; dest="${spec#*|}"
    if xcode_build "$label" "$dest"; then pass "xcodebuild $dest: BUILD SUCCEEDED, no warning"
    else fail "xcodebuild $dest: failed or warned (log lines above)"; fi
  done
fi

echo
if [ "$FAILURES" -eq 0 ]; then echo "skeleton acceptance ($MODE): all checks passed"; exit 0; fi
echo "skeleton acceptance ($MODE): $FAILURES check(s) failed"; exit 1
