#!/usr/bin/env bash
# Extra acceptance checks for TWAK-34, added by the tester next to skeleton.sh.
# skeleton.sh reads Package.swift and project.pbxproj as text; these checks ask the tools themselves
# (SwiftPM's evaluated manifest, xcodebuild's resolved build settings) and prove Swift 6 mode is really on.
#
# Usage, from the repository root:
#   Tests/Acceptance/skeleton_manifests.sh static   # evaluated manifests (swift package dump-package) and project text
#   Tests/Acceptance/skeleton_manifests.sh full     # static + resolved app build settings + Swift 6 data-race checks
#                                                   # that must fail swift build and xcodebuild (default)
set -uo pipefail

MODE="${1:-full}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/twak34-manifests.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

FAILURES=0
pass() { printf 'ok   %s\n' "$1"; }
fail() { printf 'FAIL %s\n' "$1"; FAILURES=$((FAILURES + 1)); }
check() { local name="$1"; shift; if "$@" >/dev/null 2>&1; then pass "$name"; else fail "$name"; fi; }

PACKAGES=(Domain AppShared DesignSystem MatrixData)
PBX=TwakeChat.xcodeproj/project.pbxproj

# ---------------------------------------------------------------- static
# The manifest as SwiftPM evaluates it. --disable-sandbox only skips the manifest sandbox, which cannot nest
# inside another sandbox; these are local manifests from this repository.
for p in "${PACKAGES[@]}"; do
  if ! swift package --disable-sandbox --package-path "Packages/$p" dump-package >"$WORK/$p.json" 2>"$WORK/$p.err"; then
    fail "$p: SwiftPM evaluates Package.swift ($(grep -m1 error: "$WORK/$p.err"))"; continue
  fi
  pass "$p: SwiftPM evaluates Package.swift"
  python3 -I - "$p" "$WORK/$p.json" <<'PY'
import json, sys
name, path = sys.argv[1], sys.argv[2]
m = json.load(open(path))
# ADR 0005 dependency table, plus the platforms the card asks for.
deps = {"Domain": [], "AppShared": [], "DesignSystem": [], "MatrixData": ["appshared", "domain"]}
platforms = {"Domain": [("ios", "18.0"), ("macos", "15.0")], "AppShared": [("ios", "18.0"), ("macos", "15.0")],
             "DesignSystem": [("ios", "18.0")], "MatrixData": [("ios", "18.0")]}
def report(ok, text):
    print(("ok   " if ok else "FAIL ") + f"{name} (evaluated): {text}")
    return 0 if ok else 1
bad = 0
bad += report(m["toolsVersion"]["_version"] == "6.2.0", f"tools version 6.2.0 (got {m['toolsVersion']['_version']})")
# No package-wide language-mode override: tools 6.2 means Swift 6 mode.
modes = m.get("swiftLanguageVersions") or m.get("swiftLanguageModes")
bad += report(modes in (None, ["6"]), f"package language modes are Swift 6 only (got {modes})")
got_deps = sorted(next(iter(d.values()))[0]["identity"] for d in m["dependencies"])
bad += report(got_deps == deps[name], f"package dependencies {got_deps} match ADR 0005 {deps[name]}")
remote = [d for d in m["dependencies"] if "fileSystem" not in d]
bad += report(not remote, "every package dependency is a local path (no Matrix SDK yet)")
got_platforms = sorted((x["platformName"], x["version"]) for x in m["platforms"])
bad += report(got_platforms == platforms[name], f"platforms {got_platforms}")
targets = m["targets"]
bad += report([(t["name"], t["type"]) for t in targets] == [(name, "regular")],
              f"one regular target named {name}, no test target (got {[(t['name'], t['type']) for t in targets]})")
products = m["products"]
bad += report([(x["name"], x["targets"], list(x["type"])) for x in products] == [(name, [name], ["library"])],
              f"one library product {name}")
for t in targets:
    kinds = [s["kind"] for s in t["settings"]]
    bad += report(kinds == [{"treatAllWarnings": {"_0": "error"}}],
                  f"target settings are only treatAllWarnings(as: .error), no unsafeFlags or language-mode downgrade (got {kinds})")
    tdeps = []
    for d in t["dependencies"]:
        kind, val = next(iter(d.items()))
        tdeps.append((kind, val[0], val[1] if kind == "product" else None))
    want = [("product", "Domain", "Domain"), ("product", "AppShared", "AppShared")] if name == "MatrixData" else []
    bad += report(sorted(tdeps) == sorted(want), f"target dependencies {tdeps}")
sys.exit(1 if bad else 0)
PY
  [ $? -eq 0 ] || FAILURES=$((FAILURES + 1))
done

# The card: "Each has one source file so the package compiles". Exactly one Swift file, at Sources/<Name>/<Name>.swift,
# and no other file under Sources (no resource, no second placeholder, no Tests folder: test targets are card b).
for p in "${PACKAGES[@]}"; do
  files="$(cd "Packages/$p" && find Sources -type f ! -name .DS_Store | sort | tr '\n' ' ' | sed 's/ $//')"
  [ "$files" = "Sources/$p/$p.swift" ] && pass "$p: exactly one source file, Sources/$p/$p.swift" \
    || fail "$p: source files are '$files', the card asks for one (Sources/$p/$p.swift)"
  check "$p: no Tests folder (test targets are card b)" test ! -e "Packages/$p/Tests"
done

# Matrix SDK: no reference in any form (import kinds, @_exported, package reference, product name).
check "no Matrix SDK name in Swift sources, manifests or the project file" bash -c \
  "! grep -rnE 'MatrixRust|matrix-rust|MatrixSDK' --include='*.swift' --include='*.pbxproj' --include='*.xcscheme' TwakeChat Packages TwakeChat.xcodeproj"
check "project has no remote package reference" bash -c "! grep -q XCRemoteSwiftPackageReference '$PBX'"
check "project has no .xcconfig base configuration (out of scope)" bash -c "! grep -q baseConfigurationReference '$PBX'"
check "no version check anywhere in the repository's Swift code" bash -c \
  "! grep -rnE --include='*.swift' '#(un)?available|@available' --exclude-dir=.build --exclude-dir=DerivedData ."

# The project graph, followed by object id: the app's sources come in through the synchronized TwakeChat folder
# (the Sources phase is empty), and every package product is really in the target's Frameworks phase.
python3 -I - "$PBX" <<'PY'
import re, sys
text = open(sys.argv[1]).read()
objs = {}
for m in re.finditer(r'^\t\t([0-9A-F]{24})(?: /\*[^*]*\*/)? = \{\n(.*?)^\t\t\};', text, re.S | re.M):
    objs[m.group(1)] = m.group(2)
for m in re.finditer(r'^\t\t([0-9A-F]{24})(?: /\*[^*]*\*/)? = (\{[^\n]*\});$', text, re.M):
    objs[m.group(1)] = m.group(2)
def field(body, key):
    body = re.sub(r'\s*/\*.*?\*/', '', body)
    m = re.search(rf'\b{key} = (\((.*?)\)|"?([^";]*)"?);', body, re.S)
    if not m: return None
    return re.findall(r'([0-9A-F]{24})', m.group(2)) if m.group(2) is not None else m.group(3)
bad = 0
def report(ok, msg):
    global bad
    print(("ok   " if ok else "FAIL ") + msg); bad += 0 if ok else 1
targets = [b for b in objs.values() if 'isa = PBXNativeTarget' in b]
t = targets[0]
groups = [objs[i] for i in field(t, 'fileSystemSynchronizedGroups') or []]
report(any('PBXFileSystemSynchronizedRootGroup' in g and field(g, 'path') == 'TwakeChat' for g in groups),
       "TwakeChat target compiles the synchronized TwakeChat/ folder (TwakeChatApp.swift, RootView.swift)")
phases = [objs[i] for i in field(t, 'buildPhases')]
fw = [p for p in phases if 'PBXFrameworksBuildPhase' in p]
linked = set()
for f in (field(fw[0], 'files') if fw else []):
    ref = field(objs[f], 'productRef')
    if ref and ref in objs: linked.add(field(objs[ref], 'productName'))
want = {"Domain", "AppShared", "DesignSystem", "MatrixData"}
report(linked == want, f"Frameworks phase links exactly {sorted(want)} (got {sorted(linked)})")
deps = {field(objs[i], 'productName') for i in field(t, 'packageProductDependencies') or []}
report(deps == want, f"packageProductDependencies are exactly {sorted(want)} (got {sorted(deps)})")
proj = [b for b in objs.values() if 'isa = PBXProject' in b][0]
refs = {field(objs[i], 'relativePath') for i in field(proj, 'packageReferences') or []}
report(refs == {f"Packages/{n}" for n in want}, f"project package references are the four local packages (got {sorted(refs)})")
sys.exit(1 if bad else 0)
PY
[ $? -eq 0 ] || FAILURES=$((FAILURES + 1))

# ---------------------------------------------------------------- full
if [ "$MODE" = full ]; then
  IOS_SDK="$(xcrun --sdk iphonesimulator --show-sdk-path)"

  # The resolved build settings of the app target, in both configurations.
  for config in Debug Release; do
    if xcodebuild -showBuildSettings -project TwakeChat.xcodeproj -target TwakeChat -configuration "$config" \
         >"$WORK/settings-$config.txt" 2>"$WORK/settings-$config.err"; then
      setting() { grep -E "^[[:space:]]+$1 = " "$WORK/settings-$config.txt" | head -1 | sed -E 's/^[^=]*= ?//'; }
      for kv in SWIFT_VERSION=6.0 SWIFT_STRICT_CONCURRENCY=complete SWIFT_TREAT_WARNINGS_AS_ERRORS=YES \
                GCC_TREAT_WARNINGS_AS_ERRORS=YES IPHONEOS_DEPLOYMENT_TARGET=18.0 \
                PRODUCT_BUNDLE_IDENTIFIER=app.twake.ios.chat GENERATE_INFOPLIST_FILE=YES SDKROOT=iphoneos \
                DEVELOPMENT_TEAM= CODE_SIGN_ENTITLEMENTS= SWIFT_SUPPRESS_WARNINGS=NO; do
        key="${kv%%=*}"; want="${kv#*=}"; got="$(setting "$key")"
        [ "$got" = "$want" ] && pass "$config: resolved $key = '$want'" || fail "$config: resolved $key = '$got', expected '$want'"
      done
      sdkver="$(setting SDK_VERSION)"
      case "$sdkver" in 26*) pass "$config: built with the iOS 26 SDK ($sdkver)" ;; *) fail "$config: SDK_VERSION '$sdkver', ADR 0002 needs iOS 26" ;; esac
    else
      fail "$config: xcodebuild -showBuildSettings ($(grep -m1 -i error "$WORK/settings-$config.err"))"
    fi
  done

  # Swift 6 mode is really on: nonisolated global mutable state is an error in Swift 6 and accepted in Swift 5.
  RACE='public var twak34SharedCounter = 0'
  RACE_ERR="error: .*twak34SharedCounter.*not concurrency-safe"
  cp -R Packages "$WORK/race"; rm -rf "$WORK"/race/*/.build "$WORK"/race/*/.swiftpm
  for p in "${PACKAGES[@]}"; do
    printf '%s\n' "$RACE" > "$WORK/race/$p/Sources/$p/Race.swift"
    case "$p" in
      Domain|AppShared) args=() ;;
      *) args=(--triple arm64-apple-ios26.0-simulator --sdk "$IOS_SDK") ;;
    esac
    check "$p: shared mutable global state fails swift build (Swift 6 mode)" bash -c \
      "! swift build --package-path '$WORK/race/$p' ${args[*]+${args[*]}} >'$WORK/race-$p.log' 2>&1 && grep -qE '$RACE_ERR' '$WORK/race-$p.log'"
    rm -f "$WORK/race/$p/Sources/$p/Race.swift"
  done

  mkdir -p "$WORK/race-app"
  cp -R TwakeChat TwakeChat.xcodeproj Packages "$WORK/race-app/"; rm -rf "$WORK"/race-app/Packages/*/.build
  printf '%s\n' "$RACE" > "$WORK/race-app/TwakeChat/Race.swift"
  check "app target: shared mutable global state fails xcodebuild (Swift 6 mode)" bash -c \
    "cd '$WORK/race-app' && ! xcodebuild build -project TwakeChat.xcodeproj -scheme TwakeChat \
       -destination 'generic/platform=iOS Simulator' -derivedDataPath '$WORK/dd-race-app' >'$WORK/race-app.log' 2>&1 \
     && grep -qE 'Race\.swift:[0-9]+:[0-9]+: $RACE_ERR' '$WORK/race-app.log'"

  # Error path: a warning inside an iOS-only package must fail the app build. Xcode passes -suppress-warnings to
  # packages it treats as outside dependencies, which would hide it; DesignSystem is built only through this scheme.
  mkdir -p "$WORK/neg-pkg"
  cp -R TwakeChat TwakeChat.xcodeproj Packages "$WORK/neg-pkg/"; rm -rf "$WORK"/neg-pkg/Packages/*/.build "$WORK"/neg-pkg/Packages/*/.swiftpm
  printf 'func twak34PackageWarning() { var unused = 1; _ = unused }\n' > "$WORK/neg-pkg/Packages/DesignSystem/Sources/DesignSystem/Warning.swift"
  check "a warning in DesignSystem fails the app xcodebuild as an error" bash -c \
    "cd '$WORK/neg-pkg' && ! xcodebuild build -project TwakeChat.xcodeproj -scheme TwakeChat \
       -destination 'generic/platform=iOS Simulator' -derivedDataPath '$WORK/dd-neg-pkg' >'$WORK/neg-pkg.log' 2>&1 \
     && grep -qE 'DesignSystem/Warning\.swift:[0-9]+:[0-9]+: error: .*never mutated' '$WORK/neg-pkg.log'"

  # The built product: a clean generic-simulator build has no warning, and its Info.plist carries the ADR values.
  if xcodebuild build -project TwakeChat.xcodeproj -scheme TwakeChat -destination 'generic/platform=iOS Simulator' \
       -derivedDataPath "$WORK/dd-product" >"$WORK/product.log" 2>&1 \
     && grep -q '\*\* BUILD SUCCEEDED \*\*' "$WORK/product.log" && ! grep -q 'warning:' "$WORK/product.log"; then
    pass "generic iOS Simulator build: BUILD SUCCEEDED, no warning"
    check "no module of the app build is compiled with -suppress-warnings" bash -c "! grep -q -- '-suppress-warnings' '$WORK/product.log'"
    APP="$(find "$WORK/dd-product/Build/Products" -maxdepth 2 -name TwakeChat.app -type d | head -1)"
    plist() { /usr/libexec/PlistBuddy -c "Print :$1" "$APP/Info.plist" 2>/dev/null; }
    [ "$(plist CFBundleIdentifier)" = app.twake.ios.chat ] && pass "built app: CFBundleIdentifier app.twake.ios.chat" \
      || fail "built app: CFBundleIdentifier '$(plist CFBundleIdentifier)'"
    [ "$(plist MinimumOSVersion)" = 18.0 ] && pass "built app: MinimumOSVersion 18.0" \
      || fail "built app: MinimumOSVersion '$(plist MinimumOSVersion)'"
    case "$(plist DTSDKName)" in iphonesimulator26*) pass "built app: built with the iOS 26 SDK ($(plist DTSDKName))" ;;
      *) fail "built app: DTSDKName '$(plist DTSDKName)', ADR 0002 needs iOS 26" ;; esac
    check "built app: no app extension or entitlements (out of scope)" bash -c \
      "[ ! -d '$APP/PlugIns' ] && ! codesign -d --entitlements - '$APP' 2>/dev/null | grep -q 'application-groups\|keychain-access-groups'"
  else
    grep -E 'warning:|error:' "$WORK/product.log" | sort -u | head -20 >&2
    fail "generic iOS Simulator build: failed or warned (log lines above)"
  fi
fi

echo
if [ "$FAILURES" -eq 0 ]; then echo "skeleton manifests ($MODE): all checks passed"; exit 0; fi
echo "skeleton manifests ($MODE): $FAILURES check(s) failed"; exit 1
