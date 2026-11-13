#!/usr/bin/env bash
# Acceptance checks for TWAK-67 (set up the Matrix SDK platform at launch), added by the tester next to
# authentication.sh. MatrixDataTests/MatrixPlatformTests covers the behaviour (two calls and many concurrent calls do
# not crash). This script covers the card's rules that a unit test cannot see, because the configuration is private:
#   - MatrixPlatform.setUp() is the first statement of TwakeChatApp.init, before any client is built (ADR 0004);
#   - initPlatform is called in MatrixPlatform.swift only, with the full tokio runtime (ADR 0006);
#   - the logs carry no message content: no trace log packs, never debug or trace, Release at warn and written nowhere,
#     no files, no Sentry, and setUp() logs nothing of its own (ADR 0009);
#   - the public API of MatrixPlatform names no SDK type (ADR 0006);
#   - the Data Layer page and the troubleshooting page name the call.
#
# Usage, from the repository root:
#   Tests/Acceptance/platform.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

FAILURES=0
pass() { printf 'ok   %s\n' "$1"; }
fail() { printf 'FAIL %s\n' "$1"; FAILURES=$((FAILURES + 1)); }

APP=TwakeChat/TwakeChatApp.swift
PLATFORM=Packages/MatrixData/Sources/MatrixData/MatrixPlatform.swift

# ---------------------------------------------------------------- launch order (ADR 0004)
[ -f "$PLATFORM" ] || fail "$PLATFORM exists"
first="$(awk '
  /^[[:space:]]*init\(\)[[:space:]]*\{/ { inside = 1; next }
  inside && !/^[[:space:]]*(\/\/.*)?$/ { sub(/^[[:space:]]+/, ""); print; exit }' "$APP")"
if [ "$first" = "MatrixPlatform.setUp()" ]; then pass "MatrixPlatform.setUp() is the first statement of TwakeChatApp.init"
else fail "the first statement of TwakeChatApp.init is '$first', not MatrixPlatform.setUp()"; fi

callers="$(grep -rn 'MatrixPlatform\.setUp()' TwakeChat Packages --include='*.swift' 2>/dev/null | grep -v '/\.build/' || true)"
if [ "$(printf '%s\n' "$callers" | grep -c .)" -eq 1 ] && printf '%s' "$callers" | grep -q "^$APP:"; then
  pass "the app calls MatrixPlatform.setUp() once, in TwakeChatApp.swift"
else fail "MatrixPlatform.setUp() is called elsewhere or more than once:"; printf '%s\n' "$callers"; fi

# ---------------------------------------------------------------- one caller of initPlatform (ADR 0006)
init_callers="$(grep -rln 'initPlatform(' TwakeChat Packages Tests --include='*.swift' 2>/dev/null | grep -v '/\.build/' || true)"
if [ "$init_callers" = "$PLATFORM" ]; then pass "initPlatform is called in MatrixPlatform.swift only"
else fail "initPlatform is called in: $(echo "$init_callers" | tr '\n' ' ')"; fi
if grep -q 'useLightweightTokioRuntime: false' "$PLATFORM"; then pass "the app uses the full tokio runtime"
else fail "the app does not pass useLightweightTokioRuntime: false"; fi

# ---------------------------------------------------------------- no message content in logs (ADR 0009)
code="$(grep -vE '^[[:space:]]*//' "$PLATFORM")"
if printf '%s' "$code" | grep -q 'traceLogPacks: \[\]'; then pass "no trace log packs"
else fail "traceLogPacks is not the empty list"; fi
if printf '%s' "$code" | grep -qE '\.(debug|trace)\b'; then fail "a debug or trace log level is used"
else pass "the log level is never debug or trace"; fi
if printf '%s' "$code" | grep -q 'writeToFiles: nil' && printf '%s' "$code" | grep -q 'sentryConfig: nil'; then
  pass "no log files and no Sentry"
else fail "writeToFiles or sentryConfig is not nil"; fi

release="$(awk '/^[[:space:]]*#if DEBUG/ { d = 1; next } d && /^[[:space:]]*#else/ { r = 1; next }
  r && /^[[:space:]]*#endif/ { exit } r { print }' "$PLATFORM")"
if printf '%s' "$release" | grep -q 'LogLevel.warn' && printf '%s' "$release" | grep -q 'writeToStdoutOrSystem = false'; then
  pass "Release logs at warn and writes nowhere"
else fail "the Release branch is not warn with no stdout or system output: $release"; fi
debug="$(awk '/^[[:space:]]*#if DEBUG/ { d = 1; next } d && /^[[:space:]]*#else/ { exit } d { print }' "$PLATFORM")"
if printf '%s' "$debug" | grep -q 'LogLevel.info'; then pass "Debug logs at info"
else fail "the Debug branch is not at info: $debug"; fi

if printf '%s' "$code" | grep -qE '\b(print|debugPrint|NSLog|os_log|Logger)\('; then fail "setUp() logs on its own"
else pass "setUp() logs nothing of its own"; fi

# ---------------------------------------------------------------- public API (ADR 0006)
public_lines="$(grep -E '^[[:space:]]*public[[:space:]]' "$PLATFORM" | sed -E 's/^[[:space:]]+//; s/[[:space:]]*\{?[[:space:]]*$//')"
expected="$(printf '%s\n%s' 'public enum MatrixPlatform' 'public static func setUp()')"
if [ "$public_lines" = "$expected" ]; then pass "MatrixPlatform's public API is the enum and setUp() only, with no SDK type"
else fail "MatrixPlatform's public API is not just setUp():"; printf '%s\n' "$public_lines"; fi

# ---------------------------------------------------------------- knowledge base
if grep -q 'MatrixPlatform.setUp()' .okf/architecture/components/data.md; then pass "the Data Layer page names MatrixPlatform.setUp()"
else fail "the Data Layer page does not name MatrixPlatform.setUp()"; fi
if grep -q 'MatrixPlatform.setUp()' .okf/troubleshooting.md; then pass "the troubleshooting page names the hang and its cause"
else fail "the troubleshooting page does not name MatrixPlatform.setUp()"; fi

echo
if [ "$FAILURES" -eq 0 ]; then echo "platform acceptance: all checks passed"; else echo "platform acceptance: $FAILURES failure(s)"; fi
[ "$FAILURES" -eq 0 ]
