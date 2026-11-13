#!/usr/bin/env bash
# Acceptance checks for sign-in (the Flutter app's TwakeWelcome, company server, SSO and password flows; ADR 0021),
# launch restore and logout. The unit tests (AuthenticationTests, TwakeChatTests) cover the behaviour. This script
# covers the rules that a unit test cannot see:
#   - the feature imports only Domain, DesignSystem and system modules (no MatrixData, no SDK; ADR 0005, 0006);
#   - nothing logs, and no string interpolates the password or a token;
#   - both build configurations set the sign-in URLs of twake-on-matrix (Debug: staging `config.json`, Release: Twake
#     SaaS `ConfigurationSaas`), and no credential is committed;
#   - the app registers the `twake.chat` and `matrix` URL schemes.
#
# Usage, from the repository root:
#   Tests/Acceptance/authentication.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

FAILURES=0
pass() { printf 'ok   %s\n' "$1"; }
fail() { printf 'FAIL %s\n' "$1"; FAILURES=$((FAILURES + 1)); }

FEATURE=Packages/Features/Authentication
SOURCES="$FEATURE/Sources/Authentication"
PBX=TwakeChat.xcodeproj/project.pbxproj

files=$(find "$SOURCES" -name '*.swift' | sort)
[ -n "$files" ] || fail "the Authentication target has Swift sources"
if grep -lE '^[[:space:]]*#if[[:space:]]+DEBUG' $files >/dev/null; then
  fail "the Authentication feature has Debug-only code: Release must sign in too"
else pass "the Authentication feature is the same in Debug and Release"; fi

# ---------------------------------------------------------------- imports (ADR 0005, 0006)
bad_imports="$(grep -rhE '^[[:space:]]*(@testable[[:space:]]+)?import[[:space:]]' "$SOURCES" \
  | sed -E 's/^[[:space:]]*(@testable[[:space:]]+)?import[[:space:]]+//' | sort -u \
  | grep -vxE 'Domain|DesignSystem|SwiftUI|Foundation|Observation' || true)"
if [ -z "$bad_imports" ]; then pass "the feature imports only Domain, DesignSystem, SwiftUI, Foundation, Observation"
else fail "the feature imports other modules: $(echo "$bad_imports" | tr '\n' ' ')"; fi

# ---------------------------------------------------------------- no secret in a log or a string
log_calls="$(grep -rnE '\b(print|debugPrint|NSLog|os_log|dump)\(|\bLogger\b|\bOSLog\b' \
  --include='*.swift' "$FEATURE/Sources" TwakeChat || true)"
if [ -z "$log_calls" ]; then pass "the feature and the app target log nothing"
else fail "logging calls found:"; printf '%s\n' "$log_calls"; fi

leaks="$(grep -rnE '\\\([^)]*([Pp]assword|accessToken|refreshToken)' --include='*.swift' "$FEATURE/Sources" TwakeChat || true)"
if [ -z "$leaks" ]; then pass "no string interpolates the password or a token"
else fail "a string interpolates the password or a token:"; printf '%s\n' "$leaks"; fi

# ---------------------------------------------------------------- build configuration (no credentials)
python3 - "$PBX" <<'PY'
import re, sys
text = open(sys.argv[1]).read()
blocks = re.findall(r'[0-9A-F]{24} /\* (\w+) \*/ = \{\s*isa = XCBuildConfiguration;(.*?)\n\t\t\};', text, re.S)
bad = 0
def report(ok, msg):
    global bad
    print(("ok   " if ok else "FAIL ") + msg)
    bad += 0 if ok else 1
expected = {
    "Debug": {
        "TWAKE_DEFAULT_HOMESERVER": "https://matrix.stg.lin-saas.com/",
        "TWAKE_REGISTRATION_URL": "https://sign-up.stg.lin-saas.com/",
        "TWAKE_WORKPLACE_HOMESERVER": "https://tom.stg.lin-saas.com/",
    },
    "Release": {
        "TWAKE_DEFAULT_HOMESERVER": "https://matrix.twake.app/",
        "TWAKE_REGISTRATION_URL": "https://sign-up.twake.app/",
        "TWAKE_WORKPLACE_HOMESERVER": "https://matrix.twake.app",
    },
}
app_blocks = [(name, body) for name, body in blocks if "TWAKE_" in body]
report(sorted(n for n, _ in app_blocks) == ["Debug", "Release"],
       f"the sign-in settings are in the app's Debug and Release configurations (got {[n for n, _ in app_blocks]})")
for name, body in app_blocks:
    for key, value in expected.get(name, {}).items():
        m = re.search(key + r' = "?([^";]*)"?;', body)
        report(bool(m) and m.group(1) == value, f"{name} sets {key} to {value}")
report(not re.search(r'(?i)(password|access_?token|MATRIX_USER|stgtest)\s*=', text),
       "the project file sets no password, token or test account")
sys.exit(1 if bad else 0)
PY
[ $? -eq 0 ] || FAILURES=$((FAILURES + 1))

if grep -qiE 'password|token|stgtest' TwakeChat/Info.plist; then fail "TwakeChat/Info.plist names a password, token or test account"
else pass "TwakeChat/Info.plist holds no credential"; fi

for scheme in twake.chat matrix; do
  if grep -q "<string>$scheme</string>" TwakeChat/Info.plist; then pass "the app registers the $scheme URL scheme"
  else fail "TwakeChat/Info.plist does not register the $scheme URL scheme"; fi
done

echo
if [ "$FAILURES" -eq 0 ]; then echo "authentication acceptance: all checks passed"; else echo "authentication acceptance: $FAILURES failure(s)"; fi
[ "$FAILURES" -eq 0 ]
