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
| Format and lint | swift-format, which ships with Xcode 26 ([ADR 0014](../../docs/adr/0014-ci-github-actions-swift-format.md)); see Format and lint below |
| CI | `.github/workflows/ci.yml` on GitHub Actions ([ADR 0014](../../docs/adr/0014-ci-github-actions-swift-format.md), [ADR 0027](../../docs/adr/0027-ci-builds-and-tests-every-pull-request.md)); see CI below |
| Release build and signing | Not designed; the Flutter app uses fastlane |

Use any installed iOS 26 simulator: `xcrun simctl list devices available` lists them, and the `OS=` and `name=` values above are examples.
Builds, tests and launches run on an iOS 26 simulator only (owner decision 2026-11-12); there is no iOS 18 build or launch check.
A build passes when it ends with `** BUILD SUCCEEDED **` and the log has no `warning:` line.

## Format and lint
| Step | Command |
|---|---|
| Lint; exits non-zero on any finding | `scripts/lint.sh` |
| Format the same files in place | `scripts/lint.sh --fix` |
| Lint or format only some folders (paths from the repository root) | `scripts/lint.sh [--fix] Packages/Domain TwakeChat` |
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
- No package dependency: swift-format ships with Xcode. CI runs `scripts/lint.sh` once per module; see CI below.

## CI
`.github/workflows/ci.yml` runs on every pull request and every push to `main`. A newer run on the same ref cancels
the older one. `main` requires every job below; keep the names stable.

| Check | Runner | What it runs |
|---|---|---|
| `format (<module>)` | `ubuntu-24.04` | `scripts/lint.sh <path>` per module ([ADR 0014](../../docs/adr/0014-ci-github-actions-swift-format.md)) |
| `architecture` | `ubuntu-24.04` | `scripts/check-architecture.sh`, `scripts/check-localization.sh` and the self-tests of the architecture, no-comments and localization checks |
| `build` | `macos-26` | `xcodebuild build` of the `TwakeChat` scheme for the pinned simulator ([ADR 0027](../../docs/adr/0027-ci-builds-and-tests-every-pull-request.md)) |
| `unit tests` | `macos-26` | `swift test` in `Packages/Domain` and `Packages/AppShared`, then `xcodebuild test` with the `TwakeChat` test plan ([Test](test.md#in-ci)) |

- Format: `swift-actions/setup-swift` installs Swift 6.2 on Ubuntu, so swift-format may be slightly older than
  Xcode's; that deviation from ADR 0014 is accepted. One job per module, in parallel with `fail-fast: false`:
  `app` (`TwakeChat`), `domain`, `matrixdata`, `designsystem`, `appshared`, `features` (each `Packages/<Name>`) and
  `scripts`. A new top-level module needs a new matrix entry, or CI does not check it.
- Build and unit tests: Xcode and the simulator are pinned once at the top of the workflow, `XCODE_VERSION`
  (`26.6`) and `SIMULATOR_DESTINATION` (`platform=iOS Simulator,OS=26.5,name=iPhone 17`). To move them, pick a pair
  the image lists ([runner image readme](https://github.com/actions/runner-images/blob/main/images/macos/macos-26-arm64-Readme.md)).
  CI's Xcode (26.6) is older than the one on developers' Macs (27.2), and code must compile on both: a local build
  that passes does not prove CI passes. Swift 6.2 in Xcode 26.6 rejects code that 27.2 accepts; seen so far:
  - Static helpers of SwiftUI views are main-actor isolated, so a test that calls one needs `@MainActor` on its suite.
  - A long SwiftUI modifier chain can hit "unable to type-check this expression in reasonable time". Give implicit
    members an explicit type (`ScenePhase.active`) or move the expression into a typed property.
  - `for (a, b) in optional.map(f) ?? [] where …` over labeled tuples fails with "pattern cannot match values of
    type". Bind the tuple (`for pair in … where pair.a …`) and read its labels.
  - `let picker = try #require(picker(coordinator))`: inside `#require` or `#expect`, the helper's name resolves to
    the constant being declared ("cannot call value of non-function type"). Write `self.picker(coordinator)`.
  - Any API from the iOS 27 SDK.
- Both macOS jobs use `.github/actions/xcode-setup`: it selects Xcode, restores `build/SourcePackages` (keyed on the
  `Package.resolved`, `Package.swift` and project files) and `build/DerivedData` (per job, keyed on
  `Package.resolved`), then runs `xcodebuild -resolvePackageDependencies`. Only a green push to `main` saves
  DerivedData. Output goes through `xcbeautify --renderer github-actions`, so errors show as annotations.
- A build error, a warning (warnings are errors, see below) or a failing test fails the job. A failed `unit tests`
  run uploads `build/TestResults.xcresult` as the `unit-tests-xcresult` artifact for 7 days.
- No secrets and no signing: `permissions: contents: read`, no `secrets.*`, no `environment:`, no account or team.
- Not in CI: the knowledge-base check, the iOS 18.0 deployment-target build, snapshot tests, the staging
  integration tests (they skip, [ADR 0020](../../docs/adr/0020-opt-in-local-staging-integration-tests.md)), the E2E
  suite (`e2e.yml`, manual only), signing and release lanes, and `Tests/` in `scripts/lint.sh`'s default folders.
- Run the same commands locally with `-derivedDataPath build/DerivedData -clonedSourcePackagesDirPath
  build/SourcePackages` to reproduce a CI failure; `build/` is ignored by git. Branch protection is set by the owner
  on GitHub.

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
| App target | `IPHONEOS_DEPLOYMENT_TARGET = 18.0`, `PRODUCT_BUNDLE_IDENTIFIER = app.twake.ios.chat`, no development team yet |
| App target | `CODE_SIGN_ENTITLEMENTS = TwakeChat/TwakeChat.entitlements`: the Keychain access group `$(AppIdentifierPrefix)app.twake.ios.chat` and the App Group `group.app.twake.ios.chat` (ADR 0007, ADR 0012), and nothing else |
| Each `Package.swift` | `swift-tools-version: 6.2` (Swift 6 mode, complete concurrency checking) and `swiftSettings: [.treatAllWarnings(as: .error)]` |
| Package platforms | `Domain` and `AppShared`: iOS 18 and macOS 15; `DesignSystem` and `MatrixData`: iOS 18 |

## Requirements
- Xcode 26.2 or later (the iOS 26 SDK and Swift 6.2), and an iOS 26 simulator runtime installed.
