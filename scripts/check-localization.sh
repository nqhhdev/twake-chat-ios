#!/bin/bash
# Fails on a user-facing string literal in package code that is not localized (#90). In a package, a bare SwiftUI
# literal such as Text("Save") is looked up in the app's main bundle, not in the package's String Catalog, so it is
# never translated: package code passes text through localized("...") (Bundle.module) or Text(verbatim:) for text
# that has no words. Prints one line per finding, "Localization (#90): <path>:<line>: <literal>", and exits 1 if any.
# Checked: SwiftUI views and modifiers that take a title (Text, Button, Label, Toggle, Section, TextField, Picker,
# navigationTitle, alert, confirmationDialog, accessibilityLabel, searchable prompt, ...) with a literal that holds a
# letter once its \(...) interpolations are removed. Scans Packages/**/Sources up to a file's first #Preview; the
# app target reads its own String Catalog.
# Usage: scripts/check-localization.sh [ROOT]    ROOT defaults to the repository root
set -euo pipefail

if [ $# -gt 0 ]; then
  cd "$1"
else
  cd "$(dirname "$0")/.."
fi

[ -d Packages ] || { echo "Localization check passed: 0 Swift file(s)."; exit 0; }

swift_files=()
while IFS= read -r file; do
  swift_files+=("${file#./}")
done < <(find ./Packages \
  \( -name .build -o -name .swiftpm -o -name DerivedData -o -name Tests \) -prune \
  -o -path '*/Sources/*' -type f -name '*.swift' -print | LC_ALL=C sort)

if [ ${#swift_files[@]} -eq 0 ]; then
  echo "Localization check passed: 0 Swift file(s)."
  exit 0
fi

findings="$(perl -ne '
  BEGIN {
    $views = qr/\b(?:Text|Button|Label|Toggle|Section|TextField|SecureField|Picker|LabeledContent|Link|Menu|NavigationLink|ContentUnavailableView|Stepper|DatePicker|GroupBox|DisclosureGroup)\(\s*/;
    $modifiers = qr/\.(?:navigationTitle|accessibilityLabel|accessibilityHint|accessibilityValue|alert|confirmationDialog|help|badge)\(\s*/;
    $literal = qr/"((?:[^"\\]|\\.)*)"/;
  }
  $preview = 1 if /^#Preview\b/;
  unless ($preview || /^\s*\/\//) {
    while (/(?:$views|$modifiers|\bprompt:\s*)$literal/g) {
      my $shown = $1; my $text = $1;
      1 while $text =~ s/\\\((?:[^()]|\((?:[^()]|\([^()]*\))*\))*\)//;
      print "Localization (#90): $ARGV:$.: \"$shown\"\n" if $text =~ /[[:alpha:]]/;
    }
  }
  if (eof) { close ARGV; $preview = 0 }
' "${swift_files[@]}" < /dev/null)"

if [ -n "$findings" ]; then
  printf '%s\n' "$findings"
  echo "Localization check failed: $(printf '%s\n' "$findings" | wc -l | tr -d ' ') unlocalized literal(s)." >&2
  exit 1
fi
echo "Localization check passed: ${#swift_files[@]} Swift file(s)."
