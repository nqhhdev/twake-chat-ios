#!/bin/bash
# Tests .github/workflows/ci.yml (TWAK-47) without GitHub. Part 1 reads the parsed workflow and checks its triggers,
# permissions, runner, Xcode pin, step order, cache key and that it holds no secret or signing setting. Part 2 runs
# each step's `run:` script the way GitHub does (`bash -e`, the default shell) in a throwaway tree under $TMPDIR with
# stub `sudo`, `xcrun`, `xcodebuild` and scripts, and checks that a failing command turns the step red.
# Needs python3 with PyYAML. Exits non-zero if any case fails.
set -uo pipefail

repo="$(cd "$(dirname "$0")/../.." && pwd)"
workflow="$repo/.github/workflows/ci.yml"
work="$(mktemp -d "${TMPDIR:-/tmp}/ci_test.XXXXXX")"
trap 'rm -rf "$work"' EXIT

if ! python3 -I -c 'import yaml' 2> /dev/null; then
  echo "error: python3 has no PyYAML module; install it to run this test (pip3 install pyyaml)." >&2
  exit 2
fi

failures=0
cases=0

expect() {  # expect <name> <command...>: the command must exit 0
  local name="$1"
  shift
  cases=$((cases + 1))
  if "$@" > "$work/out.txt" 2>&1; then
    echo "ok   $name"
  else
    echo "FAIL $name"
    sed 's/^/     | /' "$work/out.txt"
    failures=$((failures + 1))
  fi
}

# --- Part 1: what the workflow says -------------------------------------------------------------------------------

# check <python expression over `wf` (parsed workflow), `text` (raw file), `steps` (the ci job's steps)>
check() {
  python3 -I - "$workflow" "$1" << 'EOF'
import re, sys, yaml
path, expr = sys.argv[1], sys.argv[2]
text = open(path).read()
wf = yaml.safe_load(text)
# PyYAML reads the bare key `on` as the boolean True (YAML 1.1).
wf["on"] = wf.pop(True, wf.get("on"))
job = wf["jobs"]["ci"]
steps = job["steps"]
def step(word):
    """Index of the first step whose name, uses or run contains word."""
    for i, s in enumerate(steps):
        if word in (s.get("name", "") + s.get("uses", "") + s.get("run", "")):
            return i
    raise SystemExit("no step mentions " + repr(word))
ok = eval("(" + expr.strip() + ")")
if not ok:
    raise SystemExit("false: " + expr)
EOF
}

expect "the workflow file exists and parses" check 'isinstance(wf, dict) and "ci" in wf["jobs"]'
expect "it runs on every pull request" check '"pull_request" in wf["on"] and not (wf["on"]["pull_request"] or {}).get("branches")'
expect "it runs on pushes to main only" check 'wf["on"]["push"]["branches"] == ["main"]'
expect "the token can only read contents" check 'wf["permissions"] == {"contents": "read"} and "permissions" not in job'
expect "the runner is the macos-26 image" check 'job["runs-on"] == "macos-26"'
expect "Xcode is pinned to one 26.x version" check 're.fullmatch(r"26\.\d+(\.\d+)?", str(wf["env"]["XCODE_VERSION"]))'
expect "Xcode is selected with xcode-select from the pinned version" \
  check 're.search(r"xcode-select -s \"?/Applications/Xcode_\$\{?XCODE_VERSION\}?\.app", steps[step("xcode-select")]["run"])'
expect "no setup-xcode action and no 'latest'" check '"setup-xcode" not in text and "latest" not in text.lower()'
expect "the selected Xcode prints its version" check '"xcodebuild -version" in steps[step("xcode-select")]["run"]'

expect "steps run in order: checkout, Xcode, cache, okf, lint, tests, iOS 18.0 build" check '
  step("actions/checkout") < step("xcode-select") < step("actions/cache") < step("okf.py --check")
  < step("scripts/lint.sh") < step("scripts/test.sh") < step("build-for-testing")'
expect "the knowledge-base check is the real command" check 'steps[step("okf.py")]["run"].strip() == "python3 .okf/tools/okf.py --check"'
expect "the tests step is named for iOS 26" check '"iOS 26" in steps[step("scripts/test.sh")]["name"]'
expect "the build step is named for iOS 18" check '"iOS 18" in steps[step("build-for-testing")]["name"]'

expect "no step may fail without failing the job" check '
  "continue-on-error" not in job and all("continue-on-error" not in s and "if" not in s for s in steps)
  and "|| true" not in text and "set +e" not in text'
expect "run scripts use no \${{ }} expression (values come in through env)" \
  check 'all("${{" not in s.get("run", "") for s in steps)'
expect "no line continuation is broken by trailing spaces" \
  check 'all(not re.search(r"\\\\[ \t]+\n", s.get("run", "")) for s in steps)'

expect "the simulator name goes through SIMULATOR_NAME, the variable scripts/test.sh reads" check '
  wf["env"].get("SIMULATOR_NAME") and "SIMULATOR_NAME=\"${SIMULATOR_NAME:-" in open(sys.argv[1].rsplit("/.github/", 1)[0] + "/scripts/test.sh").read()'
expect "the iOS 18.0 step builds the TwakeChat scheme and test plan without running tests (ADR 0010)" check '
  all(w in steps[step("build-for-testing")]["run"] for w in ["-scheme TwakeChat", "-testPlan TwakeChat", "generic/platform=iOS Simulator"])
  and not re.search(r"xcodebuild\s+test\b", text)'
expect "the test plan and the shared scheme it names exist" \
  test -f "$repo/TwakeChat.xctestplan" -a -f "$repo/TwakeChat.xcodeproj/xcshareddata/xcschemes/TwakeChat.xcscheme"
expect "every xcodebuild build in the workflow turns signing off" check '
  all("CODE_SIGNING_ALLOWED=NO" in s["run"] for s in steps if re.search(r"xcodebuild\s+(build|build-for-testing|archive)", s.get("run", "")))'

expect "the SwiftPM cache is keyed on Package.resolved" check '
  "hashFiles('"'"'**/Package.resolved'"'"')" in steps[step("actions/cache")]["with"]["key"]
  and "org.swift.swiftpm" in steps[step("actions/cache")]["with"]["path"]'

expect "no secret, token, environment or account in the workflow" check '
  not re.search(r"secrets\.|github\.token|GITHUB_TOKEN|^\s*environment:|ACTIONS_RUNTIME_TOKEN", text, re.M)'
expect "no signing identity, team, profile or Apple account" check '
  not re.search(r"DEVELOPMENT_TEAM|CODE_SIGN_IDENTITY|PROVISIONING|\.p12|\.mobileprovision|APPLE_ID|APP_STORE_CONNECT|"
                r"ASC_|FASTLANE|MATCH_|import-codesign|keychain|password|@[A-Za-z0-9.-]+\.[a-z]{2,}", text, re.I)'
expect "no hard-coded homeserver or staging account" check '
  not re.search(r"stgtest|MATRIX_(USER|PASSWORD|HOMESERVER)|lin-saas|https?://(?!github\.com)", text, re.I)'

# --- Part 2: a failing command turns the step red -----------------------------------------------------------------

# Writes each step's run script to $work/steps/<index>.sh and the workflow env to $work/env.sh.
mkdir -p "$work/steps"
python3 -I - "$workflow" "$work" << 'EOF'
import shlex, sys, yaml
wf = yaml.safe_load(open(sys.argv[1]))
out = sys.argv[2]
with open(out + "/env.sh", "w") as f:
    for k, v in wf.get("env", {}).items():
        f.write("export %s=%s\n" % (k, shlex.quote(str(v))))
for i, s in enumerate(wf["jobs"]["ci"]["steps"]):
    if "run" in s:
        name = ("lint" if "lint.sh" in s["run"] else "tests" if "test.sh" in s["run"]
                else "build18" if "build-for-testing" in s["run"] else "xcode" if "xcode-select" in s["run"]
                else "okf" if "okf.py" in s["run"] else "step%d" % i)
        open("%s/steps/%s.sh" % (out, name), "w").write(s["run"])
EOF

# A fake repository root with stub scripts, and stub tools first on PATH. Each stub appends its call to $CALLS
# and exits 1 when "$tool $*" matches the pattern $FAIL_ON.
mkdir -p "$work/bin" "$work/root/scripts" "$work/root/.okf/tools"
for tool in sudo xcodebuild scripts/test.sh scripts/lint.sh; do
  target="$work/bin/$tool"
  case "$tool" in scripts/*) target="$work/root/$tool" ;; esac
  cat > "$target" << EOF
#!/bin/bash
echo "$tool \$*" >> "\$CALLS"
case "$tool \$*" in \$FAIL_ON) exit 1 ;; esac
exit 0
EOF
  chmod +x "$target"
done
# xcrun simctl list runtimes prints $RUNTIMES.
cat > "$work/bin/xcrun" << 'EOF'
#!/bin/bash
echo "xcrun $*" >> "$CALLS"
[ "$*" = "simctl list runtimes" ] && printf '%s\n' "$RUNTIMES" && exit 0
exit 2
EOF
chmod +x "$work/bin/xcrun"

ios26='== Runtimes ==
iOS 26.2 (26.2 - 23C54) - com.apple.CoreSimulator.SimRuntime.iOS-26-2'
no_ios26='== Runtimes ==
iOS 18.6 (18.6 - 22G86) - com.apple.CoreSimulator.SimRuntime.iOS-18-6'

status=0
run_step() {  # run_step <case> <step> <FAIL_ON pattern> <RUNTIMES>
  local dir="$work/$1"
  mkdir -p "$dir"
  : > "$dir/calls"
  (
    cd "$work/root" || exit 99
    # shellcheck disable=SC1091
    . "$work/env.sh"
    PATH="$work/bin:$PATH" CALLS="$dir/calls" FAIL_ON="$3" RUNTIMES="$4" bash -e "$work/steps/$2.sh"
  ) > "$dir/out" 2>&1
  status=$?
}

for s in xcode okf lint tests build18; do
  expect "step '$s' was found in the workflow" test -f "$work/steps/$s.sh"
done

run_step xcode-ok xcode 'none' "$ios26"
expect "Select Xcode: passes and selects the pinned app" \
  grep -qx "sudo xcode-select -s /Applications/Xcode_$(. "$work/env.sh"; echo "$XCODE_VERSION").app" "$work/xcode-ok/calls"
run_step xcode-missing xcode 'sudo xcode-select*' "$ios26"
expect "Select Xcode: a version the image lacks fails the step" test "$status" -ne 0

run_step tests-ok tests 'none' "$ios26"
expect "Tests: passes when test.sh passes on an iOS 26 runtime" test "$status" -eq 0
expect "Tests: prints the iOS 26 runtime in the log" grep -q '^iOS 26\.' "$work/tests-ok/out"
expect "Tests: test.sh gets SIMULATOR_NAME from the workflow" \
  bash -c ". '$work/env.sh' && [ -n \"\$SIMULATOR_NAME\" ] && grep -qx 'scripts/test.sh ' '$work/tests-ok/calls'"

run_step tests-red tests 'scripts/test.sh*' "$ios26"
expect "Tests: a failing test turns the step red" test "$status" -ne 0

run_step tests-no26 tests 'none' "$no_ios26"
expect "Tests: no iOS 26 runtime turns the step red" test "$status" -ne 0
expect "Tests: and test.sh does not run" bash -c "! grep -q 'scripts/test.sh' '$work/tests-no26/calls'"

run_step lint-red lint 'scripts/lint.sh*' "$ios26"
expect "Lint: a lint finding turns the step red" test "$status" -ne 0

run_step build18-ok build18 'none' "$ios26"
expect "iOS 18.0 build: passes when xcodebuild passes" test "$status" -eq 0
expect "iOS 18.0 build: runs one build-for-testing with signing off" \
  bash -c "[ \$(grep -c '^xcodebuild build-for-testing .*CODE_SIGNING_ALLOWED=NO' '$work/build18-ok/calls') -eq 1 ]"
run_step build18-red build18 'xcodebuild*' "$ios26"
expect "iOS 18.0 build: a compile error turns the step red" test "$status" -ne 0

echo "$((cases - failures))/$cases passed"
[ "$failures" -eq 0 ]
