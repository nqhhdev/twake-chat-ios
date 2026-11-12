#!/usr/bin/env bash
# Acceptance checks for TWAK-65 (password login, launch restore, logout), added by the tester next to skeleton.sh.
# The unit tests (AuthenticationTests, TwakeChatTests) cover the behaviour. This script covers the card's rules that a
# unit test cannot see:
#   - the password flow is reachable only under #if DEBUG (ADR 0019): every Authentication source is wrapped in it, and
#     the app target uses the feature only inside #if DEBUG blocks;
#   - the feature imports only Domain, DesignSystem and system modules (no MatrixData, no SDK; ADR 0005, 0006);
#   - nothing logs, and no string interpolates the password or a token;
#   - the default homeserver is set in the Debug build configuration only, and no credential is committed.
# With RELEASE_APP set to a built Release TwakeChat.app, it also checks that the Release binary holds no sign-in text.
#
# Usage, from the repository root:
#   Tests/Acceptance/authentication.sh
#   RELEASE_APP=path/to/Release-iphonesimulator/TwakeChat.app Tests/Acceptance/authentication.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

FAILURES=0
pass() { printf 'ok   %s\n' "$1"; }
fail() { printf 'FAIL %s\n' "$1"; FAILURES=$((FAILURES + 1)); }

FEATURE=Packages/Features/Authentication
SOURCES="$FEATURE/Sources/Authentication"
PBX=TwakeChat.xcodeproj/project.pbxproj

# ---------------------------------------------------------------- Debug only (ADR 0019)
# Each feature source: the first line that is not a comment or blank is `#if DEBUG`, the last non-blank one `#endif`,
# and there is no #else (which would put code in Release).
files=$(find "$SOURCES" -name '*.swift' | sort)
[ -n "$files" ] || fail "the Authentication target has Swift sources"
for f in $files; do
  first="$(grep -vE '^[[:space:]]*(//.*)?$' "$f" | head -1)"
  last="$(grep -vE '^[[:space:]]*$' "$f" | tail -1)"
  if [ "$first" = "#if DEBUG" ] && [ "$last" = "#endif" ] && ! grep -qE '^[[:space:]]*#(else|elseif)' "$f"; then
    pass "$f is wrapped in #if DEBUG"
  else
    fail "$f is not wholly inside #if DEBUG (first code line '$first', last line '$last')"
  fi
done

# The app target names the feature only inside #if DEBUG (an #else branch of #if DEBUG is Release).
outside="$(awk '
  /^[[:space:]]*#if[[:space:]]/ { n++; dbg[n] = ($0 ~ /#if[[:space:]]+DEBUG[[:space:]]*$/) ? 1 : 0; next }
  /^[[:space:]]*#else/ { if (dbg[n] == 1) dbg[n] = 0; next }
  /^[[:space:]]*#endif/ { n--; next }
  /import Authentication$|AuthenticationCoordinator|RestoreFailedScreen|PasswordLogin|SignedIn(Screen|ViewModel)/ {
    inside = 0; for (i = 1; i <= n; i++) if (dbg[i] == 1) inside = 1
    if (!inside) print FILENAME ":" FNR ": " $0
  }' TwakeChat/*.swift)"
if [ -z "$outside" ]; then pass "the app target uses the Authentication feature only under #if DEBUG"
else fail "the app target uses the Authentication feature outside #if DEBUG:"; printf '%s\n' "$outside"; fi

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
setting = [(name, re.search(r'TWAKE_DEFAULT_HOMESERVER = "?([^";]*)"?;', body)) for name, body in blocks]
setting = [(name, m.group(1)) for name, m in setting if m]
report([n for n, _ in setting] == ["Debug"],
       f"TWAKE_DEFAULT_HOMESERVER is set in exactly one build configuration, Debug (got {setting})")
report(all(v == "https://matrix.stg.lin-saas.com" for _, v in setting),
       "the Debug default homeserver is the staging homeserver")
report(not re.search(r'(?i)(password|access_?token|MATRIX_USER|stgtest)\s*=', text),
       "the project file sets no password, token or test account")
sys.exit(1 if bad else 0)
PY
[ $? -eq 0 ] || FAILURES=$((FAILURES + 1))

if grep -qiE 'password|token|stgtest' TwakeChat/Info.plist; then fail "TwakeChat/Info.plist names a password, token or test account"
else pass "TwakeChat/Info.plist holds no credential"; fi

# ---------------------------------------------------------------- optional: the Release binary
if [ -n "${RELEASE_APP:-}" ]; then
  binary="$RELEASE_APP/TwakeChat"
  if [ ! -f "$binary" ]; then
    fail "RELEASE_APP has no TwakeChat binary: $binary"
  else
    # A Debug build may put the code in TwakeChat.debug.dylib; a Release build has none, so read whatever is there.
    # Only the form's own text is searched: type names also appear as source and object file paths in the debug map
    # of a Release binary, even when no code from those files is linked.
    found="$(LC_ALL=C grep -aohE 'Please enter your password|Please enter your Matrix Id or username|Could not log out\. Please try again\.' \
      "$binary" "$RELEASE_APP"/TwakeChat.debug.dylib 2>/dev/null | sort -u || true)"
    if [ -z "$found" ]; then pass "the Release binary holds no password sign-in text"
    else fail "the Release binary holds password sign-in code: $(echo "$found" | tr '\n' ' ')"; fi
  fi
fi

echo
if [ "$FAILURES" -eq 0 ]; then echo "authentication acceptance: all checks passed"; else echo "authentication acceptance: $FAILURES failure(s)"; fi
[ "$FAILURES" -eq 0 ]
