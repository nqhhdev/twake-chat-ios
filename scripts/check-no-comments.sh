#!/bin/bash
# Fails on any comment in a Swift file (ADR 0025). Prints one line per comment,
# "Rule 6 (ADR 0025): <path>:<line>: comment", and exits 1 if there is any.
# A comment is //, ///, /* */ or /** */ outside a string or #/regex/# literal. The only line allowed is the first line of a
# Package.swift when it is `// swift-tools-version:...`, which SwiftPM requires.
# Scans *.swift files; skips build output, nested worktrees (.claude, worktrees) and the test fixtures under scripts/tests.
# Usage: scripts/check-no-comments.sh [ROOT]    ROOT defaults to the repository root
set -euo pipefail

if [ $# -gt 0 ]; then
  cd "$1"
else
  cd "$(dirname "$0")/.."
fi

swift_files=()
while IFS= read -r file; do
  swift_files+=("${file#./}")
done < <(find . \
  \( -name .git -o -name .build -o -name .swiftpm -o -name DerivedData -o -name SourcePackages \
     -o -name .claude -o -name worktrees -o -name build \) -prune \
  -o -path ./scripts/tests/architecture-fixtures -prune \
  -o -type f -name '*.swift' -print | LC_ALL=C sort)

# Prints the line number of each comment in a Swift file. Walks the source once, keeping a stack of string
# literals and of the interpolations inside them, so a "//" in "https://..." or in a multi-line or raw string
# is not a comment. Block comments nest, as in Swift.
comment_lines_of() {
  perl -0777 -ne '
    my $s = $_; my $n = length $s; my $i = 0; my $line = 1; my %seen;
    my @stack = ({ kind => "code", parens => 0 });
    my $hit = sub { print "$line\n" unless $seen{$line}++ };
    while ($i < $n) {
      my $c = substr($s, $i, 1);
      my $top = $stack[-1];
      if ($c eq "\n") { $line++; $i++; next }
      if ($top->{kind} eq "code") {
        if (substr($s, $i, 2) eq "//") {
          $hit->(); $i++ while $i < $n && substr($s, $i, 1) ne "\n"; next;
        }
        if (substr($s, $i, 2) eq "/*") {
          $hit->(); my $depth = 1; $i += 2;
          while ($i < $n && $depth > 0) {
            my $two = substr($s, $i, 2);
            if ($two eq "/*") { $depth++; $i += 2; next }
            if ($two eq "*/") { $depth--; $i += 2; next }
            if (substr($s, $i, 1) eq "\n") { $line++; $hit->() }
            $i++;
          }
          next;
        }
        if ($c eq "#" || $c eq "\"") {
          my $j = $i; $j++ while $j < $n && substr($s, $j, 1) eq "#";
          my $hashes = $j - $i;
          if ($hashes > 0 && substr($s, $j, 1) eq "/") {
            my $end = "/" . ("#" x $hashes); my $k = index($s, $end, $j + 1);
            if ($k >= 0) { $line += (substr($s, $i, $k - $i) =~ tr/\n//); $i = $k + length $end; next }
          }
          if (substr($s, $j, 1) eq "\"") {
            my $multi = substr($s, $j, 3) eq "\"\"\"";
            push @stack, { kind => "string", hashes => $hashes, multi => $multi };
            $i = $j + ($multi ? 3 : 1); next;
          }
          $i = $j > $i ? $j : $i + 1; next;
        }
        if ($c eq "(") { $top->{parens}++; $i++; next }
        if ($c eq ")") {
          $top->{parens}--; $i++;
          pop @stack if @stack > 1 && $top->{parens} == 0;
          next;
        }
        $i++; next;
      }
      my $close = ($top->{multi} ? "\"\"\"" : "\"") . ("#" x $top->{hashes});
      if (substr($s, $i, length $close) eq $close) { pop @stack; $i += length $close; next }
      my $escape = "\\" . ("#" x $top->{hashes});
      if (substr($s, $i, length $escape) eq $escape) {
        $i += length $escape;
        if (substr($s, $i, 1) eq "(") { push @stack, { kind => "code", parens => 1 }; $i++ }
        elsif ($top->{hashes} == 0 && substr($s, $i, 1) ne "\n") { $i++ }
        next;
      }
      $i++;
    }
  ' "$1"
}

violations=0
for file in ${swift_files[@]+"${swift_files[@]}"}; do
  while read -r line; do
    if [ "$line" = 1 ] && [ "$(basename "$file")" = Package.swift ] \
      && head -1 "$file" | grep -qE '^// swift-tools-version:'; then
      continue
    fi
    echo "Rule 6 (ADR 0025): $file:$line: comment"
    violations=$((violations + 1))
  done < <(comment_lines_of "$file")
done

if [ "$violations" -gt 0 ]; then
  echo "No-comments check failed: $violations comment line(s)." >&2
  exit 1
fi
echo "No-comments check passed: ${#swift_files[@]} Swift file(s)."
