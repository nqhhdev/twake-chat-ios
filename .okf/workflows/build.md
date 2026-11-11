---
type: Workflow
title: "Build"
description: "How the project will be built and checked; commands are planned until the Xcode project exists."
tags: [build, ci]
status: draft
---
# Build

> Not runnable yet: the repository has no Xcode project. Replace this page with the real commands when it is created.

## Planned
| Step | Tool |
|---|---|
| Resolve dependencies | Swift Package Manager through Xcode; `Package.resolved` is committed |
| Build the app | `xcodebuild` for the `TwakeChat` scheme, on an iOS 26 simulator and an iOS 18 simulator |
| Build one package alone | `swift build` inside `Packages/<Name>` where the package has no iOS-only dependency, otherwise `xcodebuild` |
| Format and lint | swift-format, which ships with Xcode 26 ([ADR 0014](../adr/0014-ci-github-actions-swift-format.md)); runnable now, see below |
| CI | GitHub Actions on GitHub-hosted macOS runners ([ADR 0014](../adr/0014-ci-github-actions-swift-format.md)); no workflow file yet |
| Release build and signing | Not designed; the Flutter app uses fastlane |

## Format and lint
| Step | Command |
|---|---|
| Lint; exits non-zero on any finding | `scripts/lint.sh` |
| Format the same files in place | `scripts/lint.sh --fix` |
| Test the lint script itself | `scripts/tests/lint_test.sh` (throwaway trees under `$TMPDIR`; reports the `--fix` cases as skipped where swift-format cannot save in place) |

- The style is `.swift-format` at the repository root. It is exactly swift-format's defaults
  (`xcrun swift-format dump-configuration`, swift-format 6.2.3 from Xcode 26.2): no rule is turned off or changed.
  Any later change to it gets a line here with its reason.
- The script runs `xcrun swift-format lint --strict --parallel` over the `.swift` files under `TwakeChat/`,
  `Packages/` and `scripts/`, the folders that exist. `--strict` turns warnings into errors.
- swift-format has no exclude option, so the script builds the file list with `find` and prunes `.build`,
  `DerivedData` and `.swiftpm`. A tree that holds deliberate violations (such as architecture-check fixtures)
  must be added to that prune list in the same change that creates it.
- No package dependency: swift-format ships with Xcode. Lint does not run in CI yet.

## Requirements
- Xcode with the iOS 26 SDK, and an iOS 18 simulator runtime installed.
