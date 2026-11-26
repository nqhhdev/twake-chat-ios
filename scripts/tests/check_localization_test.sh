#!/bin/bash
# Tests scripts/check-localization.sh (#90) on throwaway trees under $TMPDIR: each `clean-*` tree must pass; each
# `bare-*` tree holds exactly one unlocalized literal and must fail with exactly one "Localization (#90)" line naming
# that line. Exits non-zero if any case fails.
set -uo pipefail

repo="$(cd "$(dirname "$0")/../.." && pwd)"
work="$(mktemp -d "${TMPDIR:-/tmp}/check_localization_test.XXXXXX")" || exit 1
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

check() {  # check <case> [<line>]: no line means the tree must pass, a line means one finding there
  local name="$1" want="${2:-}" out status
  out="$(bash "$repo/scripts/check-localization.sh" "$work/$name" 2>&1)"
  status=$?
  local hits; hits="$(printf '%s\n' "$out" | grep -E '^Localization \(#90\): ' || true)"
  if [ -z "$want" ]; then
    expect "$name" "exits 0" test "$status" -eq 0
    expect "$name" "reports nothing" test -z "$hits"
  else
    expect "$name" "exits 1" test "$status" -eq 1
    expect "$name" "reports exactly one literal" test "$(printf '%s\n' "$hits" | grep -c '^Localization ')" -eq 1
    expect "$name" "names line $want" grep -qE ":$want: " <<< "$hits"
  fi
  [ "$status" -eq 0 ] || [ -n "$want" ] || printf '     %s\n' "$hits"
}

src=Packages/Features/Demo/Sources/Demo/View.swift

put clean-localized "$src" 'Text(localized("Save"))
Button(localized("Cancel")) {}
.navigationTitle(localized("Chats"))'
check clean-localized

put clean-wordless "$src" 'Text(verbatim: "Twake Chat")
Text("\(count)")
Text("\(name) · \(date.formatted())")
Text("")
Text("+\(hidden)")'
check clean-wordless

put clean-preview "$src" 'Text(localized("Save"))
#Preview {
  Text("Preview only")
}'
check clean-preview

put clean-app TwakeChat/RootView.swift 'Text("The app target reads its own catalog")'
check clean-app

put clean-tests Packages/Features/Demo/Tests/DemoTests/ViewTests.swift 'Text("Tests are not shipped")'
check clean-tests

put bare-text "$src" 'Text(localized("Save"))
Text("Save")'
check bare-text 2

put bare-button-image "$src" 'Button("Choose Photo", systemImage: "photo") {}'
check bare-button-image 1

put bare-modifier "$src" 'VStack {}
  .accessibilityLabel("Close")'
check bare-modifier 2

put bare-prompt "$src" 'List {}
  .searchable(text: $query, prompt: "Search chats")'
check bare-prompt 2

put bare-interpolated "$src" 'Text("\(count) members")'
check bare-interpolated 1

put bare-after-a-preview-file Packages/DesignSystem/Sources/DesignSystem/A.swift '#Preview { Text("Preview only") }'
put bare-after-a-preview-file Packages/DesignSystem/Sources/DesignSystem/B.swift 'Text("Online")'
check bare-after-a-preview-file 1

echo "$((cases - failures))/$cases checks passed."
[ "$failures" -eq 0 ]
