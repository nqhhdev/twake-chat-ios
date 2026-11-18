#!/bin/bash
# Lints every Swift file with swift-format against .swift-format; exits non-zero on any finding.
# Usage: scripts/lint.sh                 check only
#        scripts/lint.sh --fix           rewrite the same files in place with `swift-format format`
#        scripts/lint.sh [--fix] PATH... only these folders or files, relative to the repository root
#                                        (CI checks one module per job)
set -euo pipefail

cd "$(dirname "$0")/.."

usage() { echo "usage: $0 [--fix] [path ...]" >&2; exit 2; }

mode=lint
roots=()
for arg in "$@"; do
  case "$arg" in
    --fix) mode=format ;;
    -*) usage ;;
    *)
      [ -e "$arg" ] || { echo "$0: no such path: $arg" >&2; exit 2; }
      roots+=("$arg")
      ;;
  esac
done

if [ ${#roots[@]} -eq 0 ]; then
  for dir in TwakeChat Packages scripts; do
    [ -d "$dir" ] && roots+=("$dir")
  done
fi
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

# Xcode's swift-format on a Mac; the Swift 6 toolchain's `swift format` on Linux CI.
run_swift_format() {
  if command -v xcrun >/dev/null 2>&1 && xcrun --find swift-format >/dev/null 2>&1; then
    xcrun swift-format "$@"
  elif command -v swift-format >/dev/null 2>&1; then
    swift-format "$@"
  elif command -v swift >/dev/null 2>&1; then
    swift format "$@"
  else
    echo "$0: swift-format not found (install Xcode or a Swift 6 toolchain)" >&2
    exit 1
  fi
}

if [ "$mode" = format ]; then
  run_swift_format format --in-place --parallel -- "${files[@]}"
else
  run_swift_format lint --strict --parallel -- "${files[@]}"
fi
