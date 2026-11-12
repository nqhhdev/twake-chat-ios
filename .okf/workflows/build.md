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
| Resolve dependencies | Swift Package Manager through Xcode resolves on the first build. `Package.resolved` is committed once the project has a remote dependency |
| Build the app, iOS 26 | `xcodebuild build -project TwakeChat.xcodeproj -scheme TwakeChat -destination 'platform=iOS Simulator,OS=26.2,name=iPhone 17'` |
| Build without a simulator runtime | `xcodebuild build -project TwakeChat.xcodeproj -scheme TwakeChat -destination 'generic/platform=iOS Simulator'` |
| Build a package that also targets macOS | `cd Packages/Domain && swift build`, and the same in `Packages/AppShared` |
| Build an iOS-only package | `DesignSystem` and `MatrixData` declare iOS only, so build them through the app scheme |
| Format and lint | swift-format, which ships with Xcode 26 ([ADR 0014](../adr/0014-ci-github-actions-swift-format.md)); see Format and lint below |
| CI | GitHub Actions on GitHub-hosted macOS runners ([ADR 0014](../adr/0014-ci-github-actions-swift-format.md)); no workflow file yet |
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
- No package dependency: swift-format ships with Xcode. Lint does not run in CI yet.

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
