#!/bin/bash
# Lints every Swift file with swift-format against .swift-format; exits non-zero on any finding.
# Usage: scripts/lint.sh          check only
#        scripts/lint.sh --fix    rewrite the same files in place with `swift-format format`
set -euo pipefail

cd "$(dirname "$0")/.."

mode=lint
case "${1:-}" in
  "") ;;
  --fix) mode=format ;;
  *) echo "usage: $0 [--fix]" >&2; exit 2 ;;
esac

roots=()
for dir in TwakeChat Packages scripts; do
  [ -d "$dir" ] && roots+=("$dir")
done
[ ${#roots[@]} -eq 0 ] && exit 0

# swift-format has no exclude option, so the file list is built here.
# Pruned: build output, and trees that hold deliberate violations.
files=()
while IFS= read -r -d '' file; do
  files+=("$file")
done < <(find "${roots[@]}" \
  \( -name .build -o -name DerivedData -o -name .swiftpm \) -prune \
  -o -type f -name '*.swift' -print0)
[ ${#files[@]} -eq 0 ] && exit 0

if [ "$mode" = format ]; then
  xcrun swift-format format --in-place --parallel -- "${files[@]}"
else
  xcrun swift-format lint --strict --parallel -- "${files[@]}"
fi
