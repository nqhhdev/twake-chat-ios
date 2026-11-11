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

# 12. A lint-only finding, one `format` cannot repair (a naming rule), still fails: --strict applies to
# every rule, not only to whitespace.
r=$(new_repo lint-only)
put "$r" Packages/Core/Sources/Core/Naming.swift $'let Bad_name = 1\n'
expect "a lint-only (naming) finding fails" nonzero "$r/scripts/lint.sh"

# 13. The script lints against the repository's own .swift-format, not swift-format's built-in defaults,
# also when run from another directory. A 4-space style makes the 4-space file clean and the 2-space one a finding.
r=$(new_repo own-config)
sed 's/"spaces" : 2/"spaces" : 4/' "$repo/.swift-format" > "$r/.swift-format"
four=$'struct Sample {\n    let value: Int\n}\n'
put "$r" Packages/Core/Sources/Core/Four.swift "$four"
expect "the committed .swift-format is used (4-space file passes)" 0 \
  bash -c "cd '$work' && '$r/scripts/lint.sh'"
put "$r" TwakeChat/App/Two.swift "$good"
expect "the committed .swift-format is used (2-space file fails)" nonzero \
  bash -c "cd '$work' && '$r/scripts/lint.sh'"

# 14. A file that does not parse is a failure, not silently skipped.
r=$(new_repo parse-error)
put "$r" Packages/Core/Sources/Core/Good.swift "$good"
put "$r" Packages/Core/Sources/Core/Broken.swift $'struct Broken {\n  let value: Int\n'
expect "a file that does not parse fails" nonzero "$r/scripts/lint.sh"

# 15. Lint only checks: a misformatted file is left byte-for-byte unchanged.
r=$(new_repo check-only)
put "$r" Packages/Core/Sources/Core/Bad.swift "$bad"
expect "lint reports the misformatted file" nonzero "$r/scripts/lint.sh"
expect "lint did not rewrite the file" 0 \
  diff "$work/bad.swift" "$r/Packages/Core/Sources/Core/Bad.swift"

# 16. --fix and lint hand swift-format the same pruned file list. A fake `xcrun` on PATH records its
# arguments, so this runs even where swift-format cannot save in place (case 9 is then skipped).
fake="$work/fake-bin"
mkdir -p "$fake"
cat > "$fake/xcrun" <<'EOF'
#!/bin/bash
printf '%s\n' "$@" > "$FAKE_XCRUN_LOG"
exit "${FAKE_XCRUN_EXIT:-0}"
EOF
chmod +x "$fake/xcrun"
r=$(new_repo same-list)
put "$r" Packages/Core/Sources/Core/A.swift "$good"
put "$r" "Packages/My Package/Sources/B File.swift" "$good"
put "$r" TwakeChat/App/C.swift "$good"
put "$r" scripts/D.swift "$good"
put "$r" Packages/Core/.build/E.swift "$good"
put "$r" Packages/Core/.swiftpm/F.swift "$good"
put "$r" TwakeChat/DerivedData/G.swift "$good"
put "$r" proposals/H.swift "$good"
printf '%s\n' Packages/Core/Sources/Core/A.swift "Packages/My Package/Sources/B File.swift" \
  TwakeChat/App/C.swift scripts/D.swift | sort > "$work/expected.files"
expect "lint calls swift-format through the fake" 0 \
  env PATH="$fake:$PATH" FAKE_XCRUN_LOG="$work/lint.args" "$r/scripts/lint.sh"
expect "--fix calls swift-format through the fake" 0 \
  env PATH="$fake:$PATH" FAKE_XCRUN_LOG="$work/fix.args" "$r/scripts/lint.sh" --fix
expect "lint runs 'swift-format lint --strict'" 0 \
  bash -c "head -3 '$work/lint.args' | tr '\n' ' ' | grep -q '^swift-format lint --strict '"
expect "--fix runs 'swift-format format --in-place'" 0 \
  bash -c "head -3 '$work/fix.args' | tr '\n' ' ' | grep -q '^swift-format format --in-place '"
sed '1,/^--$/d' "$work/lint.args" | sort > "$work/lint.files"
sed '1,/^--$/d' "$work/fix.args" | sort > "$work/fix.files"
expect "lint gets exactly the unpruned files under the three roots" 0 \
  diff "$work/expected.files" "$work/lint.files"
expect "--fix gets the same file list as lint" 0 diff "$work/lint.files" "$work/fix.files"

# 17. A swift-format failure in --fix mode (for example, a file it cannot save) makes the script fail.
expect "--fix fails when swift-format fails" nonzero \
  env PATH="$fake:$PATH" FAKE_XCRUN_LOG="$work/fail.args" FAKE_XCRUN_EXIT=1 "$r/scripts/lint.sh" --fix

echo "$((cases - failures))/$cases passed"
[ "$failures" -eq 0 ]
