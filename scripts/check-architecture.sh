#!/bin/bash
# Checks the import and package rules the compiler cannot enforce (TWAK-36). Prints one line per violation,
# "Rule N (ADR 000X): <path>:<line>: <what is wrong>", and exits 1 if there is any.
#   Rule 1 (ADR 0006): only Packages/MatrixData imports the Matrix SDK or declares its package.
#   Rule 2 (ADR 0002): no #available / @available(iOS outside Packages/DesignSystem.
#   Rule 3 (ADR 0005): each package depends only on the local packages ADR 0005 allows; no feature on a feature.
#   Rule 4 (ADR 0005): Domain, AppShared and DesignSystem sources import only the system modules ADR 0005 allows.
#   Rule 5 (ADR 0003): a Package.swift that declares the Matrix SDK pins it with exact:.
# Scans *.swift and Package.swift files; skips build output and the test fixtures under scripts/tests.
# Usage: scripts/check-architecture.sh [ROOT]    ROOT defaults to the repository root
set -euo pipefail

if [ $# -gt 0 ]; then
  cd "$1"
else
  cd "$(dirname "$0")/.."
fi

sdk_package="matrix-rust-components-swift"
# Modules of matrix-rust-components-swift 26.04.01 (ADR 0015), read from its Package.swift: the MatrixRustSDK
# product and the MatrixSDKFFI binary target behind it.
sdk_modules=" MatrixRustSDK MatrixSDKFFI "

violations=0
report() {  # report <rule> <adr> <path:line> <message>
  echo "Rule $1 (ADR $2): $3: $4"
  violations=$((violations + 1))
}

# Prints the package a path belongs to (Domain, AppShared, DesignSystem, MatrixData, Features/<X>) or "outside".
owner_of() {
  case "$1" in
    Packages/Domain/*) echo Domain ;;
    Packages/AppShared/*) echo AppShared ;;
    Packages/DesignSystem/*) echo DesignSystem ;;
    Packages/MatrixData/*) echo MatrixData ;;
    Packages/Features/*/*)
      local rest="${1#Packages/Features/}"
      echo "Features/${rest%%/*}"
      ;;
    *) echo outside ;;
  esac
}

# Prints "<line> <module>" for each import in a Swift file. Accepts attributes (@testable, @_exported,
# @preconcurrency, ...), access levels (public/package/internal/... import) and kind imports (import struct X.Y).
# Several statements on one line count one by one: `import Foundation; import SwiftUI` is two imports.
imports_of() {
  awk '{
    n = split($0, parts, ";")
    for (i = 1; i <= n; i++) {
      s = parts[i]
      sub(/^[ \t]+/, "", s)
      while (match(s, /^@[A-Za-z_]+(\([^)]*\))?[ \t]+/)) s = substr(s, RLENGTH + 1)
      if (match(s, /^(public|package|internal|fileprivate|private|open)[ \t]+/)) s = substr(s, RLENGTH + 1)
      if (!match(s, /^import[ \t]+/)) continue
      s = substr(s, RLENGTH + 1)
      if (match(s, /^(typealias|struct|class|enum|protocol|let|var|func)[ \t]+/)) s = substr(s, RLENGTH + 1)
      if (match(s, /^[A-Za-z_][A-Za-z0-9_]*/)) print NR, substr(s, 1, RLENGTH)
    }
  }' "$1"
}

# Prints "<line> <path>" for each .package(... path: "...") call in a manifest, also when the call spans lines.
local_dependencies_of() {
  awk '
    {
      line = $0
      sub(/(^|[ \t])\/\/.*$/, "", line)
      for (i = 1; i <= length(line); i++) {
        if (depth == 0 && substr(line, i, 9) == ".package(") {
          depth = 1; start = NR; text = ""; i += 8; continue
        }
        if (depth > 0) {
          c = substr(line, i, 1)
          if (c == "(") depth++
          if (c == ")") depth--
          if (depth == 0) {
            if (match(text, /path:[ \t]*"[^"]*"/)) {
              m = substr(text, RSTART, RLENGTH)
              sub(/^path:[ \t]*"/, "", m)
              sub(/"$/, "", m)
              print start, m
            }
          } else {
            text = text c
          }
        }
      }
      if (depth > 0) text = text " "
    }' "$1"
}

# Prints "<line> <ok|bad>" for each .package(...) call that declares the SDK: ok when it pins with exact: only.
# A call declares the SDK when its text names the package, or when its url: is a constant whose string names it
# (let sdkURL = "https://github.com/.../matrix-rust-components-swift" then .package(url: sdkURL, ...)).
# The manifest is read twice: first to collect those constants, then to judge the calls.
sdk_requirements_of() {
  awk -v sdk="$sdk_package" '
    NR == FNR {
      line = $0
      sub(/(^|[ \t])\/\/.*$/, "", line)
      if (index(line, sdk) > 0 && match(line, /(let|var)[ \t]+[A-Za-z_][A-Za-z0-9_]*/)) {
        name = substr(line, RSTART, RLENGTH)
        sub(/^(let|var)[ \t]+/, "", name)
        sdk_names[name] = 1
      }
      next
    }
    {
      line = $0
      sub(/(^|[ \t])\/\/.*$/, "", line)  # a line comment, not the "//" of a URL
      for (i = 1; i <= length(line); i++) {
        if (depth == 0 && substr(line, i, 9) == ".package(") {
          depth = 1; start = NR; text = ""; i += 8; continue
        }
        if (depth > 0) {
          c = substr(line, i, 1)
          if (c == "(") depth++
          if (c == ")") depth--
          if (depth == 0) {
            is_sdk = (index(text, sdk) > 0)
            if (!is_sdk && match(text, /url:[ \t]*[A-Za-z_][A-Za-z0-9_]*/)) {
              ref = substr(text, RSTART, RLENGTH)
              sub(/^url:[ \t]*/, "", ref)
              is_sdk = (ref in sdk_names)
            }
            if (is_sdk) {
              exact = (text ~ /exact:/)
              other = (text ~ /(from|branch|revision|upToNextMajor|upToNextMinor):|\.\.\.|\.\.</)
              print start, ((exact && !other) ? "ok" : "bad")
            }
          } else {
            text = text c
          }
        }
      }
      if (depth > 0) text = text " "
    }' "$1" "$1"
}

# Joins a manifest's folder and a relative path and removes "." and ".." parts.
normalize_path() {
  awk -v p="$1/$2" 'BEGIN {
    n = split(p, parts, "/"); k = 0
    for (i = 1; i <= n; i++) {
      if (parts[i] == "" || parts[i] == ".") continue
      if (parts[i] == "..") { if (k > 0) k--; continue }
      out[++k] = parts[i]
    }
    s = ""; for (i = 1; i <= k; i++) s = s (i > 1 ? "/" : "") out[i]
    print s
  }'
}

swift_files=()
while IFS= read -r file; do
  swift_files+=("${file#./}")
done < <(find . \
  \( -name .git -o -name .build -o -name .swiftpm -o -name DerivedData -o -name SourcePackages \) -prune \
  -o -path ./scripts/tests/architecture-fixtures -prune \
  -o -type f -name '*.swift' -print | LC_ALL=C sort)

for file in ${swift_files[@]+"${swift_files[@]}"}; do
  owner="$(owner_of "$file")"

  # Rules 1 and 4: imports.
  while read -r line module; do
    if [ "$owner" != MatrixData ] && [[ "$sdk_modules" == *" $module "* ]]; then
      report 1 0006 "$file:$line" "import $module outside Packages/MatrixData; only MatrixData may import the Matrix SDK"
    fi
    case "$file" in
      Packages/Domain/Sources/*) allowed="Foundation" ;;
      Packages/AppShared/Sources/*) allowed="Foundation Security OSLog" ;;
      Packages/DesignSystem/Sources/*) allowed="SwiftUI" ;;
      *) continue ;;
    esac
    if [[ " $allowed " != *" $module "* ]]; then
      report 4 0005 "$file:$line" "$owner may import only $allowed, found import $module"
    fi
  done < <(imports_of "$file")

  # Rule 2: version checks. iOS may be any argument of @available, e.g. @available(macOS 15, iOS 18, *),
  # and any platform starting with iOS counts, e.g. @available(iOSApplicationExtension 26, *).
  # #unavailable is the same check inverted, e.g. if #unavailable(iOS 26) { ... }.
  # Every @available attribute counts, however many share a line and however swift-format wraps them (it does at
  # 100 columns): the file is read whole, comments are blanked (keeping line numbers), and the line where each
  # attribute starts is reported.
  if [ "$owner" != DesignSystem ]; then
    while IFS=: read -r line _; do
      report 2 0002 "$file:$line" "iOS version check outside Packages/DesignSystem"
    done < <( { grep -nE '#(un)?available' "$file" || true
                perl -0777 -ne '
                  my $src = $_;
                  $src =~ s{/\*.*?\*/}{ (my $c = $&) =~ s/[^\n]/ /g; $c }gse;
                  $src =~ s{//[^\n]*}{ " " x length($&) }ge;
                  while ($src =~ /\@available\s*\(([^)]*)\)/g) {
                    my ($args, $at) = ($1, $-[0]);
                    next unless $args =~ /(^|[^A-Za-z0-9_])iOS/;
                    print 1 + (substr($src, 0, $at) =~ tr/\n//), ":\n";
                  }' "$file"; } | sort -u -t: -k1,1n)
  fi

  [ "$(basename "$file")" = Package.swift ] || continue

  # Rule 1: the SDK package declared outside MatrixData.
  if [ "$owner" != MatrixData ]; then
    while IFS=: read -r line _; do
      report 1 0006 "$file:$line" "$sdk_package declared outside Packages/MatrixData"
    done < <(grep -nF "$sdk_package" "$file" || true)
  fi

  # Rule 5: exact SDK pin.
  while read -r line verdict; do
    if [ "$verdict" = bad ]; then
      report 5 0003 "$file:$line" "$sdk_package must be pinned with exact:"
    fi
  done < <(sdk_requirements_of "$file")

  # Rule 3: local package dependencies.
  case "$owner" in
    Domain | AppShared | DesignSystem) allowed="" ;;
    MatrixData) allowed="Domain AppShared" ;;
    Features/*) allowed="Domain DesignSystem" ;;
    *) continue ;;
  esac
  while read -r line path; do
    target="$(normalize_path "$(dirname "$file")" "$path")"
    target_owner="$(owner_of "$target/")"
    # Judged by the package the path points at, not by its last part: ../Features/Domain is a feature, not Domain.
    name="$target_owner"
    [ "$name" = outside ] && name="$(basename "$path")"
    if [[ "$owner" == Features/* && "$target_owner" == Features/* ]]; then
      report 3 0005 "$file:$line" "feature $owner depends on feature $target_owner; a feature must not depend on another feature"
    elif [ -z "$allowed" ]; then
      report 3 0005 "$file:$line" "$owner may depend on no local package, found $name"
    elif [[ " $allowed " != *" $name "* ]]; then
      report 3 0005 "$file:$line" "$owner may depend only on ${allowed// / and }, found $name"
    fi
  done < <(local_dependencies_of "$file")
done

if [ "$violations" -gt 0 ]; then
  echo "Architecture check failed: $violations violation(s)." >&2
  exit 1
fi
echo "Architecture check passed: ${#swift_files[@]} Swift file(s), rules 1-5."
