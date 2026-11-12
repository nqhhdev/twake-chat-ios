---
type: Workflow
title: "Test"
description: "How to run every unit test with one command, where each test target lives, and which part needs a simulator."
tags: [test, ci, ios-26]
status: draft
---
# Test

Run every command from the repository root.

## Commands
| Step | Command |
|---|---|
| Every unit test; stops with a non-zero exit code on the first failure | `scripts/test.sh` |
| Pick another iOS 26 simulator | `SIMULATOR_NAME='iPhone 17 Pro' scripts/test.sh` (default `iPhone 17`) |
| Host-only tests, no simulator | `swift test --package-path Packages/Domain`, then the same for `Packages/AppShared` |
| Simulator tests only | `xcodebuild test -project TwakeChat.xcodeproj -scheme TwakeChat -testPlan TwakeChat -destination 'platform=iOS Simulator,OS=26.0.1,name=iPhone 17'` (`OS=` must match the installed runtime exactly; `xcrun simctl list devices available` shows it) |
| Test the test script itself | `scripts/tests/test_test.sh` (stub `swift`, `xcrun` and `xcodebuild`; no Xcode needed) |
| Architecture rules only (ADRs 0002, 0003, 0005, 0006; see [Constraints](../engineering/constraints.md)) | `scripts/check-architecture.sh [ROOT]` |
| Test the architecture check on its fixture trees | `scripts/tests/check_architecture_test.sh` (trees in `scripts/tests/architecture-fixtures/`) |

`scripts/test.sh` runs in this order:
1. `scripts/check-architecture.sh` on the repository, then `scripts/tests/check_architecture_test.sh`. Both are text
   scans and take well under a second.
2. `swift test` in `Packages/Domain` and `Packages/AppShared` on the macOS host. Both packages declare macOS 15, so no
   simulator boots. The script prints how long this part took: about 10 s from a clean `.build` (SwiftPM reported
   5.1 s and 3.8 s of build on an Apple silicon Mac, 2026-11-12), and about 1 s each when nothing changed.
3. `xcodebuild test` with the `TwakeChat` test plan on the first available simulator named `$SIMULATOR_NAME` under an
   iOS 26.x runtime. If there is none, the script exits non-zero and says so. The test run itself took about 15 s
   after the build.

A failure in any step stops the script before the next one. There is no iOS 18 test run (owner decision 2026-11-12).

## In CI
The `ci` job ([Build](build.md#ci)) runs `scripts/test.sh` once, on an iOS 26 simulator, on every pull request and
push to `main`. It then compiles the app and the test plan against the iOS 18.0 deployment target without running the
tests again. Snapshot and integration tests do not run in CI.

## Test targets
| Target | Lives in | Runs with |
|---|---|---|
| `DomainTests` | `Packages/Domain/Tests/DomainTests/` | `swift test`, host |
| `AppSharedTests` | `Packages/AppShared/Tests/AppSharedTests/` | `swift test`, host |
| `MatrixDataTests` | `Tests/MatrixDataTests/`, a synchronized folder of the project; links the `MatrixData` product, not hosted by the app | test plan, iOS 26 simulator |
| `DesignSystemTests` | `Packages/DesignSystem/Tests/DesignSystemTests/` | test plan, iOS 26 simulator |
| `TwakeChatTests` | `Tests/TwakeChatTests/`, a synchronized folder of the project | test plan, iOS 26 simulator, hosted by the app |

- `MatrixDataTests` is a project target, not a package test target, because `MatrixData` declares iOS only (its SDK
  binary will be iOS-only) and a package with a `Tests` folder is run with host `swift test`, which cannot build it.
  Keep `Packages/MatrixData` without a `Tests` folder.
- `DesignSystem` declares iOS only too, but builds on the host (SwiftUI exists on macOS), so `swift test` also passes
  there. `scripts/test.sh` still runs it on the simulator, where the snapshot tests will run.
- The test plan is `TwakeChat.xctestplan` at the repository root, the default plan of the `TwakeChat` scheme. It lists
  only the three simulator targets, so `DomainTests` and `AppSharedTests` do not run twice.
- A new package test target goes in its `Package.swift` with `swiftSettings: [.treatAllWarnings(as: .error)]`. If it
  runs on the simulator, add it to the test plan too.
- `TwakeChatTests` uses `@testable import TwakeChat`; package tests use plain `import` of the module's public API.
- Swift Testing only (`import Testing`, `@Test`, `#expect`), and no mocking library
  ([ADR 0010](../adr/0010-testing-strategy-two-ios-versions.md)).

## Planned
| Kind | Where | Runs on |
|---|---|---|
| Snapshot tests of `DesignSystem` | `DesignSystem` test target; the tool is not chosen | Not decided; ADR 0010 asks for iOS 18 and iOS 26 |
| Integration tests with a homeserver | Opt-in, local only: staging credentials from `~/.factos/secrets/twake-chat-ios-staging.env` or the `MATRIX_HOMESERVER`, `MATRIX_USER`, `MATRIX_PASSWORD` environment variables; a test skips when they are absent ([ADR 0017](../adr/0017-opt-in-local-staging-integration-tests.md)) | A developer's machine; never CI |

## Writing a test for a view model
1. Create fakes of the Domain protocols the view model needs.
2. Build the view model with them.
3. Call an action; assert on the view model's state.
