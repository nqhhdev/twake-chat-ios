#!/bin/bash
# Tests scripts/check-no-comments.sh (ADR 0025) on throwaway trees under $TMPDIR: each `clean-*` tree must pass;
# each `comment-*` tree holds exactly one comment line and must fail with exactly one "Rule 6 (ADR 0025)" line
# naming that line. Exits non-zero if any case fails.
set -uo pipefail

repo="$(cd "$(dirname "$0")/../.." && pwd)"
work="$(mktemp -d "${TMPDIR:-/tmp}/check_no_comments_test.XXXXXX")" || exit 1
trap 'rm -rf "$work"' EXIT

failures=0
cases=0

expect() {  # expect <case name> <description> <condition...>
  local name="$1" what="$2"; shift 2
  cases=$((cases + 1))
  if "$@"; then echo "ok   $name: $what"; else echo "FAIL $name: $what"; failures=$((failures + 1)); fi
}

put() {  # put <case> <path> <content>: writes one file of a case's tree
  mkdir -p "$work/$1/$(dirname "$2")"
  printf '%s\n' "$3" > "$work/$1/$2"
}

check() {  # check <case> [<line>]: no line means the tree must pass, a line means one comment there
  local name="$1" want="${2:-}" out status
  out="$(bash "$repo/scripts/check-no-comments.sh" "$work/$name" 2>&1)"
  status=$?
  local hits; hits="$(printf '%s\n' "$out" | grep -E '^Rule 6 \(ADR 0025\): ' || true)"
  if [ -z "$want" ]; then
    expect "$name" "exits 0" test "$status" -eq 0
    expect "$name" "reports no comment" test -z "$hits"
  else
    expect "$name" "exits 1" test "$status" -eq 1
    expect "$name" "reports exactly one comment" test "$(printf '%s\n' "$hits" | grep -c '^Rule ')" -eq 1
    expect "$name" "names line $want" grep -qE ":$want: comment$" <<< "$hits"
  fi
  [ "$status" -eq 0 ] || [ -n "$want" ] || printf '     %s\n' "$hits"
}

put clean-code A.swift 'let a = 1
func f() -> Int { a / 2 }'
check clean-code

put clean-url-in-string A.swift 'let url = "https://example.org/a//b"'
check clean-url-in-string

put clean-multiline-string A.swift 'let text = """
  // not a comment
  /* not a comment */
  """'
check clean-multiline-string

put clean-raw-string A.swift 'let raw = #"a "quoted" // part"#
let rawMulti = #"""
  "// still text"
  """#'
check clean-raw-string

put clean-interpolation A.swift 'let s = "a \("b//c") \(f("//")) d"'
check clean-interpolation

put clean-escaped-quote A.swift 'let s = "say \"//\" here"'
check clean-escaped-quote

put clean-regex-literal A.swift 'let r = #/[^ ]{0,100}:\/\//#'
check clean-regex-literal

put clean-tools-version Package.swift '// swift-tools-version: 6.0
import PackageDescription'
check clean-tools-version

put comment-line A.swift 'let a = 1
// a comment'
check comment-line 2

put comment-doc A.swift '/// Documents f.
func f() {}'
check comment-doc 1

put comment-mark A.swift 'struct S {}
// MARK: - Part
extension S {}'
check comment-mark 2

put comment-trailing A.swift 'let a = 1  // why'
check comment-trailing 1

put comment-after-string A.swift 'let u = "https://x" // why'
check comment-after-string 1

put comment-block A.swift 'let a = 1 /* why */'
check comment-block 1

put comment-after-interpolation A.swift 'let s = "\(a)" // why'
check comment-after-interpolation 1

put comment-tools-version-elsewhere A.swift '// swift-tools-version: 6.0'
check comment-tools-version-elsewhere 1

put comment-package-second-line Package.swift '// swift-tools-version: 6.0
// why'
check comment-package-second-line 2

put clean-skipped-folders .build/A.swift '// build output'
put clean-skipped-folders .claude/worktrees/x/A.swift '// another worktree'
put clean-skipped-folders scripts/tests/architecture-fixtures/A.swift '// a fixture'
check clean-skipped-folders

echo "$cases case(s), $failures failure(s)."
[ "$failures" -eq 0 ]
