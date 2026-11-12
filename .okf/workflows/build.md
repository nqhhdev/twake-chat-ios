---
type: Workflow
title: "Build"
description: "How to build the TwakeChat app and the local packages, and the build settings that keep Swift 6 strict and warning-free."
tags: [build, ci]
status: draft
---
# Build

Run every command from the repository root unless a step says otherwise.

## Commands
| Step | Command |
|---|---|
| Resolve dependencies | Swift Package Manager through Xcode resolves on the first build. The Matrix SDK's pin is committed in `Packages/MatrixData/Package.resolved` (run `swift package resolve` there to refresh it). Xcode 27.2 writes no workspace `Package.resolved` for this project, even with a `project.xcworkspace`, so the app build relies on the `exact:` tag, not on a locked revision (TWAK-48) |
| Build the app, iOS 26 | `xcodebuild build -project TwakeChat.xcodeproj -scheme TwakeChat -destination 'platform=iOS Simulator,OS=26.2,name=iPhone 17'` |
| Build without a simulator runtime | `xcodebuild build -project TwakeChat.xcodeproj -scheme TwakeChat -destination 'generic/platform=iOS Simulator'` |
| Build a package that also targets macOS | `cd Packages/Domain && swift build`, and the same in `Packages/AppShared` |
| Build an iOS-only package | `DesignSystem` and `MatrixData` declare iOS only, so build them through the app scheme |
| Format and lint | swift-format, which ships with Xcode 26 ([ADR 0014](../adr/0014-ci-github-actions-swift-format.md)); see Format and lint below |
| CI | `.github/workflows/ci.yml` on GitHub Actions ([ADR 0014](../adr/0014-ci-github-actions-swift-format.md)); see CI below |
| Release build and signing | Not designed; the Flutter app uses fastlane |

Use any installed iOS 26 simulator: `xcrun simctl list devices available` lists them, and the `OS=` and `name=` values above are examples.
Builds, tests and launches run on an iOS 26 simulator only (owner decision 2026-11-12); there is no iOS 18 build or launch check.
A build passes when it ends with `** BUILD SUCCEEDED **` and the log has no `warning:` line.

## Format and lint
| Step | Command |
|---|---|
| Lint; exits non-zero on any finding | `scripts/lint.sh` |
| Format the same files in place | `scripts/lint.sh --fix` |
| Test the lint script itself | `scripts/tests/lint_test.sh` (throwaway trees under `$TMPDIR`; reports the `--fix` cases as skipped where swift-format cannot save in place) |

- The style is `.swift-format` at the repository root. It is swift-format's defaults
  (`xcrun swift-format dump-configuration`, swift-format 6.2.3 from Xcode 26.2): no rule is turned off or changed,
  so indentation is 2 spaces, not Xcode's 4. A newer swift-format may know options the file does not list; they
  take their defaults. Any later change to the file gets a line here with its reason.
- `swift-format format --in-place` cannot save files inside a sandboxed shell. There, run
  `xcrun swift-format format -- <file>` and write its output back to the file.
- The script runs `xcrun swift-format lint --strict --parallel` over the `.swift` files under `TwakeChat/`,
  `Packages/` and `scripts/`, the folders that exist. `--strict` turns warnings into errors.
- swift-format has no exclude option, so the script builds the file list with `find` and prunes `.build`,
  `DerivedData` and `.swiftpm`. A tree that holds deliberate violations (such as architecture-check fixtures)
  must be added to that prune list in the same change that creates it.
- No package dependency: swift-format ships with Xcode. CI runs `scripts/lint.sh`; see CI below.

## CI
`.github/workflows/ci.yml` has one job, `ci`, on every pull request and every push to `main`. A newer run on the same
ref cancels the older one.

- Runner: the GitHub-hosted `macos-26` image. Xcode is pinned with `sudo xcode-select -s /Applications/Xcode_26.2.app`
  (`XCODE_VERSION` in the workflow), and the step prints `xcodebuild -version`. To move Xcode, change that one value to
  a version the image lists.
- Steps, in order; the first failure stops the job:
  1. `python3 .okf/tools/okf.py --check`
  2. `scripts/lint.sh`
  3. "Tests (host and iOS 26 simulator)": prints the installed iOS 26 runtimes, then `scripts/test.sh` with
     `SIMULATOR_NAME` set in the workflow (`iPhone 17`). See [Test](test.md).
  4. "Build app and tests (iOS 18.0 deployment target, no simulator)": `xcodebuild build-for-testing` of the
     `TwakeChat` scheme and test plan for `generic/platform=iOS Simulator` with `CODE_SIGNING_ALLOWED=NO`. It compiles
     the app and every test target against the iOS 18.0 deployment target (the log shows `arm64-apple-ios18.0-simulator`)
     and runs nothing, so the unit tests run once ([ADR 0010](../adr/0010-testing-strategy-two-ios-versions.md)). No
     iOS 18 runtime is installed (owner decision 2026-11-12).
- Cache: `~/Library/Caches/org.swift.swiftpm`, keyed on the runner OS, the Xcode version and
  `hashFiles('**/Package.resolved')`, so package downloads are reused until a `Package.resolved` changes.
- No secrets and no signing: `permissions: contents: read`, no `secrets.*`, no `environment:`, no account or team.
- Not in CI: snapshot tests (no tool chosen), integration tests against a homeserver (local only), signing, TestFlight
  and release lanes, the self-tests in `scripts/tests/`. Branch protection is set by the owner on GitHub.

## Layout
- `TwakeChat.xcodeproj` has one app target, `TwakeChat`, and a shared scheme of the same name. The `TwakeChat/` folder is a
  synchronized folder group, so a new Swift file in it joins the target without a project edit. The unit-test targets
  `TwakeChatTests` and `MatrixDataTests` work the same way with `Tests/TwakeChatTests/` and `Tests/MatrixDataTests/`;
  see [Test](test.md).
- The packages under `Packages/` are local package references, and the app target links all four.
- Each package folder is also a folder reference in the project's `Packages` group. Without it Xcode treats the packages as
  outside dependencies and adds `-suppress-warnings`, which conflicts with `.treatAllWarnings(as: .error)` and fails the
  build. With it, a warning in a package fails the app build as an error.
- No project generator (XcodeGen, Tuist) is used; the project file is edited by Xcode or by hand.

## Settings that enforce the rules
| Where | Setting |
|---|---|
| App target | `SWIFT_VERSION = 6.0`, `SWIFT_STRICT_CONCURRENCY = complete`, `SWIFT_TREAT_WARNINGS_AS_ERRORS = YES`, `GCC_TREAT_WARNINGS_AS_ERRORS = YES` |
| App target | `LM_SKIP_METADATA_EXTRACTION = YES`: the app has no App Intents, and the extraction step otherwise prints a `warning:` line. Remove it when the app adopts App Intents |
| App target | `IPHONEOS_DEPLOYMENT_TARGET = 18.0`, `PRODUCT_BUNDLE_IDENTIFIER = app.twake.ios.chat`, no development team or entitlements yet |
| Each `Package.swift` | `swift-tools-version: 6.2` (Swift 6 mode, complete concurrency checking) and `swiftSettings: [.treatAllWarnings(as: .error)]` |
| Package platforms | `Domain` and `AppShared`: iOS 18 and macOS 15; `DesignSystem` and `MatrixData`: iOS 18 |

## Requirements
- Xcode 26.2 or later (the iOS 26 SDK and Swift 6.2), and an iOS 26 simulator runtime installed.
