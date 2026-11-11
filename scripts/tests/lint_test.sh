#!/bin/bash
# Tests scripts/lint.sh (TWAK-46). Each case copies lint.sh and .swift-format into a throwaway
# repository layout under $TMPDIR, so the real tree is never touched. Exits non-zero if any case fails.
set -uo pipefail

repo="$(cd "$(dirname "$0")/../.." && pwd)"
work="$(mktemp -d "${TMPDIR:-/tmp}/lint_test.XXXXXX")"
trap 'rm -rf "$work"' EXIT

failures=0
cases=0

# The swift-format defaults use 2-space indentation; 4 spaces and a missing space are findings.
good=$'struct Sample {\n  let value: Int\n}\n'
bad=$'struct Sample {\n    let value:Int\n}\n'
printf '%s' "$good" > "$work/good.swift"
printf '%s' "$bad" > "$work/bad.swift"

new_repo() {
  local dir="$work/$1"
  mkdir -p "$dir/scripts"
  cp "$repo/scripts/lint.sh" "$dir/scripts/lint.sh"
  cp "$repo/.swift-format" "$dir/.swift-format"
  echo "$dir"
}

put() {  # put <repo> <relative path> <content>
  mkdir -p "$(dirname "$1/$2")"
  printf '%s' "$3" > "$1/$2"
}

expect() {  # expect <name> <expected: 0 | nonzero | N> <command...>
  local name="$1" want="$2"
  shift 2
  cases=$((cases + 1))
  "$@" > "$work/out.txt" 2>&1
  local got=$?
  local ok=0
  case "$want" in
    nonzero) [ "$got" -ne 0 ] && ok=1 ;;
    *) [ "$got" -eq "$want" ] && ok=1 ;;
  esac
  if [ "$ok" -eq 1 ]; then
    echo "ok   $name (exit $got)"
  else
    echo "FAIL $name: expected exit $want, got $got"
    sed 's/^/     | /' "$work/out.txt"
    failures=$((failures + 1))
  fi
}

# 1. The real repository is clean.
expect "repository lints clean" 0 "$repo/scripts/lint.sh"

# 2. No TwakeChat/ or Packages/, and scripts/ holds no Swift file: nothing to lint.
r=$(new_repo no-swift)
expect "no Swift files exits 0" 0 "$r/scripts/lint.sh"

# 3. A well-formatted file in every linted root passes.
r=$(new_repo good)
put "$r" Packages/Core/Sources/Core/Sample.swift "$good"
put "$r" TwakeChat/App/Sample.swift "$good"
put "$r" scripts/Tool.swift "$good"
expect "well-formatted files exit 0" 0 "$r/scripts/lint.sh"

# 4. A misformatted file under each linted root fails (--strict turns the warnings into errors).
for root in Packages/Core/Sources/Core TwakeChat/App scripts; do
  r=$(new_repo "bad-${root//\//-}")
  put "$r" Packages/Core/Sources/Core/Good.swift "$good"
  put "$r" "$root/Bad.swift" "$bad"
  expect "misformatted file in $root fails" nonzero "$r/scripts/lint.sh"
done

# 5. Misformatted files in pruned trees are skipped.
r=$(new_repo pruned)
put "$r" Packages/Core/Sources/Core/Good.swift "$good"
put "$r" Packages/Core/.build/checkouts/dep/Bad.swift "$bad"
put "$r" Packages/Core/.swiftpm/xcode/Bad.swift "$bad"
put "$r" TwakeChat/DerivedData/Build/Bad.swift "$bad"
put "$r" DerivedData/Bad.swift "$bad"
expect ".build, .swiftpm and DerivedData are skipped" 0 "$r/scripts/lint.sh"

# 6. Swift files outside TwakeChat/, Packages/ and scripts/ are not linted.
r=$(new_repo outside)
put "$r" proposals/Bad.swift "$bad"
put "$r" Bad.swift "$bad"
expect "files outside the linted roots are ignored" 0 "$r/scripts/lint.sh"

# 7. The script finds the repository root from its own location, not the current directory.
r=$(new_repo cwd)
put "$r" Packages/Core/Sources/Core/Bad.swift "$bad"
expect "run from another directory still lints" nonzero bash -c "cd '$work' && '$r/scripts/lint.sh'"
expect "run through a relative path still lints" nonzero bash -c "cd '$r/Packages' && ../scripts/lint.sh"

# 8. Paths with spaces are linted.
r=$(new_repo spaces)
put "$r" "Packages/My Package/Sources/My Module/Bad File.swift" "$bad"
expect "misformatted file in a path with spaces fails" nonzero "$r/scripts/lint.sh"

# 9. --fix formats the same files in place, after which lint passes; pruned trees are left alone.
# swift-format saves through a system temporary folder; where a sandbox forbids that, the cases are
# reported as skipped, never as passed.
probe="$work/probe"
mkdir -p "$probe"
printf '%s' "$bad" > "$probe/P.swift"
if xcrun swift-format format --in-place "$probe/P.swift" > /dev/null 2>&1; then
  r=$(new_repo fix)
  put "$r" Packages/Core/Sources/Core/Bad.swift "$bad"
  put "$r" Packages/Core/.build/Bad.swift "$bad"
  expect "--fix exits 0" 0 "$r/scripts/lint.sh" --fix
  expect "lint passes after --fix" 0 "$r/scripts/lint.sh"
  expect "--fix rewrote the file to the default style" 0 \
    diff "$work/good.swift" "$r/Packages/Core/Sources/Core/Bad.swift"
  expect "--fix left the pruned tree alone" 0 \
    diff "$work/bad.swift" "$r/Packages/Core/.build/Bad.swift"
else
  echo "SKIP --fix cases: swift-format cannot save in place in this environment"
fi

# 10. An unknown argument is rejected with exit 2 and changes nothing.
r=$(new_repo usage)
put "$r" Packages/Core/Sources/Core/Bad.swift "$bad"
expect "unknown argument exits 2" 2 "$r/scripts/lint.sh" --frobnicate
expect "unknown argument did not format" 0 \
  diff "$work/bad.swift" "$r/Packages/Core/Sources/Core/Bad.swift"

# 11. The committed style is exactly swift-format's defaults, as build.md states.
xcrun swift-format dump-configuration > "$work/defaults.json" 2> /dev/null
expect ".swift-format equals the toolchain defaults" 0 diff "$work/defaults.json" "$repo/.swift-format"

echo "$((cases - failures))/$cases passed"
[ "$failures" -eq 0 ]
