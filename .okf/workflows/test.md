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
| No comments in Swift code ([ADR 0025](../../docs/adr/0025-no-comments-in-code.md)) | `scripts/check-no-comments.sh [ROOT]`; fails on `main` until the existing comments are removed |
| Test the no-comments check | `scripts/tests/check_no_comments_test.sh` (throwaway trees under `$TMPDIR`) |
| No unlocalized SwiftUI literal in package code ([Localization](../engineering/conventions/localization.md)) | `scripts/check-localization.sh [ROOT]` |
| Test the localization check | `scripts/tests/check_localization_test.sh` (throwaway trees under `$TMPDIR`) |
| Staging integration test only ([ADR 0020](../../docs/adr/0020-opt-in-local-staging-integration-tests.md)) | `TEST_RUNNER_MATRIX_HOMESERVER=https://matrix.stg.lin-saas.com TEST_RUNNER_MATRIX_USER=stgtest1 TEST_RUNNER_MATRIX_PASSWORD=… xcodebuild test -project TwakeChat.xcodeproj -scheme TwakeChat -testPlan TwakeChat -only-testing:TwakeChatTests/AuthenticationIntegrationTests -destination 'platform=iOS Simulator,id=<iOS 26 simulator id>'`. Without the variables, the test reads `~/.factos/secrets/twake-chat-ios-staging.env` |

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
The `unit tests` job ([Build](build.md#ci), [ADR 0027](../../docs/adr/0027-ci-builds-and-tests-every-pull-request.md))
runs on every pull request and push to `main`, on `macos-26` with Xcode 26.6:
1. `swift test --package-path Packages/Domain`, then `Packages/AppShared`, on the host.
2. `xcodebuild test -project TwakeChat.xcodeproj -scheme TwakeChat -testPlan TwakeChat` on
   `platform=iOS Simulator,OS=26.5,name=iPhone 17`, with `-derivedDataPath build/DerivedData`,
   `-clonedSourcePackagesDirPath build/SourcePackages` and `-resultBundlePath build/TestResults.xcresult`.

It does not call `scripts/test.sh`: the `architecture` job already runs the architecture checks, and the script
takes no DerivedData path to cache. The staging integration suites (`AuthenticationIntegrationTests`,
`RoomListIntegrationTests`, `NotificationContentIntegrationTests`) run in the plan and skip, because CI has neither
the variables nor the env file. Snapshot tests and the iOS 18.0 deployment-target build do not run in CI. The E2E
suite (XCUITest against a local Synapse, `scripts/e2e.sh`, [docs/e2e.md](../../docs/e2e.md)) runs in its own
workflow, `.github/workflows/e2e.yml`, on dispatch and every Monday; it is not a required check of `main`.

## Test targets
| Target | Lives in | Runs with |
|---|---|---|
| `DomainTests` | `Packages/Domain/Tests/DomainTests/` | `swift test`, host |
| `AppSharedTests` | `Packages/AppShared/Tests/AppSharedTests/` | `swift test`, host |
| `MatrixDataTests` | `Tests/MatrixDataTests/`, a synchronized folder of the project; links the `MatrixData` product, not hosted by the app | test plan, iOS 26 simulator |
| `DesignSystemTests` | `Packages/DesignSystem/Tests/DesignSystemTests/` | test plan, iOS 26 simulator |
| `AuthenticationTests` | `Packages/Features/Authentication/Tests/AuthenticationTests/`; fakes in `AuthenticationTestSupport` | test plan, iOS 26 simulator |
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
- Keychain round trips of `AppShared`'s `KeychainSessionStore` run in `TwakeChatTests`
  (`KeychainSessionStoreTests.swift`), hosted by the app, because the Keychain access group needs the app's
  entitlements, which host `swift test` does not have. They use the group from the app's `KeychainAccessGroup`
  Info.plist key and the test-only service `app.twake.ios.chat.tests.keychain-session-store`, so they never touch a
  real session. The simulator signs the app locally ("Sign to Run Locally"), which is enough for the group (TWAK-63).
- `MatrixDataTests` may use `@testable import MatrixData` for the internal `UserSessionMapper`. Its signatures name
  SDK types, so it cannot be public ([ADR 0006](../../docs/adr/0006-sdk-behind-proxy-protocols.md)). The tests build the SDK
  values through the mapper or as implicit members and never import the SDK (`scripts/check-architecture.sh` rule 1).
  The target links `Domain` and `AppShared` too, because their types appear in those tests.
- The staging integration test `AuthenticationIntegrationTests` runs hosted in `TwakeChatTests`, which links
  `MatrixData` and `Domain` for it. The unhosted `MatrixDataTests` bundle has no Keychain entitlement: every Keychain
  call there fails with `-34018`, even without an access group (TWAK-64). The test uses the app's Keychain group, the
  service `app.twake.ios.chat.tests.matrix-authentication` and a temporary store directory. It never prints the
  credentials.
- Swift Testing only (`import Testing`, `@Test`, `#expect`), and no mocking library
  ([ADR 0010](../../docs/adr/0010-testing-strategy-two-ios-versions.md)).

## Planned
| Kind | Where | Runs on |
|---|---|---|
| Snapshot tests of `DesignSystem` | `DesignSystem` test target; the tool is not chosen | Not decided; ADR 0010 asks for iOS 18 and iOS 26 |
| More integration tests with a homeserver | Opt-in, local only, like `AuthenticationIntegrationTests` (below) | A developer's machine; never CI |

## Staging integration tests
`TwakeChatTests/AuthenticationIntegrationTests` (TWAK-64) logs in to staging, restores the saved session in a fresh
client on the same store, then logs out. It checks that the store directory and the Keychain item are gone
([ADR 0020](../../docs/adr/0020-opt-in-local-staging-integration-tests.md)).
- **Credentials.** It reads `MATRIX_HOMESERVER`, `MATRIX_USER` and `MATRIX_PASSWORD` from the environment, and
  otherwise from `~/.factos/secrets/twake-chat-ios-staging.env` (`KEY=value` lines). Inside the simulator, xcodebuild
  passes only variables prefixed with `TEST_RUNNER_` (it strips the prefix; the test accepts both spellings), and `~`
  is the simulated device's home, so the test finds the file through `SIMULATOR_HOST_HOME`. When a run fails or is
  skipped after login, the test awaits a sign-out of the saved session before it ends. `MATRIX_USER` is sent unchanged: give a real account (`stgtest1` …
  `stgtest20`), not the bare `stgtest` prefix.
- **Skipping.** Without the values, it skips with a message that names them, so CI and `scripts/test.sh` stay green.
  When staging rejects the credentials (`invalidCredentials`), it is cancelled with `Test.cancel` and reported as
  skipped, not failed (owner's decision of 2026-11-12).
- **When the env file exists.** Every `scripts/test.sh` run on that machine logs in to staging. It fails when
  staging is down or any step after login fails.

## Writing a test for a view model
1. Create fakes of the Domain protocols the view model needs.
2. Build the view model with them.
3. Call an action; assert on the view model's state.

## Accessibility audits and the performance budget (#96)
Both run in the E2E test plan (`TwakeChatUITests`, [docs/e2e.md](../../docs/e2e.md)) against the local homeserver of
`scripts/e2e.sh up`, never in the pull-request CI.

- **Accessibility audits** (`AccessibilityAuditFlowTests`). `performAccessibilityAudit` on Welcome, the homeserver
  picker, the password form, the chat list, a room and Settings. They fail on the types that pass today: element
  descriptions, traits and element detection (`.action` and `.parentChild` exist on macOS only). The run of
  2026-11-26 also reported, and these are not enforced yet: contrast on Welcome, Settings, the room and the chat
  list; hit areas under 44 pt (Privacy Policy, a Settings row, a message's sender and time); Dynamic Type only partly
  supported in the room timeline and the chat list's footer rows; and clipped text, which the audit often reports
  for truncated single lines. A type joins the enforced set once its screens pass. VoiceOver on a device is a manual
  check.
- **Performance budget** (`PerformanceBudgetTests`, five iterations each):

| Metric | Test | Budget | Simulator reference (iPhone 16e, iOS 26.3, Debug, 2026-11-26) |
|---|---|---|---|
| Cold launch | `testColdLaunchTime` (`XCTApplicationLaunchMetric`) | Under 400 ms to the first frame on a device, Release; under 2 s on the simulator, Debug | 0.73 s, then 1.55 s with the E2E stack starting beside it |
| Timeline scroll | `testTimelineScrollHitches` (`XCTOSSignpostMetric.scrollDecelerationMetric`, "E2E History", 300 messages) | Hitch time ratio under 5 ms/s on a device | The simulator reports only the fling's duration: 2.42 s |
| Chat list scroll | `testChatListScrollHitches` | Hitch time ratio under 5 ms/s on a device | Duration only: 0.70 s |
| Memory with a large account | Instruments, Allocations on a device | The notification extension under its system limit (about 24 MB); the app measured once, then budgeted | Device check |

  XCTest metrics fail only against a recorded baseline. None is committed: baselines are per device, and the first
  run on the reference device records them. Until then the numbers are read from the result bundle.
