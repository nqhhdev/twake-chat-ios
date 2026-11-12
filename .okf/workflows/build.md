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
| Format and lint | swift-format, which ships with Xcode 26 ([ADR 0014](../adr/0014-ci-github-actions-swift-format.md)) |
| CI | GitHub Actions on GitHub-hosted macOS runners ([ADR 0014](../adr/0014-ci-github-actions-swift-format.md)); no workflow file yet |
| Release build and signing | Not designed; the Flutter app uses fastlane |

Use any installed iOS 26 simulator: `xcrun simctl list devices available` lists them, and the `OS=` and `name=` values above are examples.
Builds, tests and launches run on an iOS 26 simulator only (owner decision 2026-11-12); there is no iOS 18 build or launch check.
A build passes when it ends with `** BUILD SUCCEEDED **` and the log has no `warning:` line.

## Layout
- `TwakeChat.xcodeproj` has one target, `TwakeChat`, and a shared scheme of the same name. The `TwakeChat/` folder is a
  synchronized folder group, so a new Swift file in it joins the target without a project edit.
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
