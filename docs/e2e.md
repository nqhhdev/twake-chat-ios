---
type: guide
title: "End-to-end UI tests (XCUITest, test plan E2E)"
description: "How to run TwakeChatUITests against a local Synapse from twake-space-chat/e2e or against staging, what each flow checks, and which element-x-ios patterns the suite follows."
tags: [testing, e2e, xcuitest]
---
# End-to-end UI tests

The `TwakeChatUITests` target drives the Debug app on a simulator against a real homeserver. It runs from its own
test plan, `E2E.xctestplan`, so `xcodebuild test` with the default plan (`TwakeChat.xctestplan`) does not start it.
Tracking issue: #83.

## Run it

```sh
scripts/e2e.sh all          # up + test + down; down runs even when a test fails
# or step by step
scripts/e2e.sh up           # Docker stack, sliding-sync check, users and rooms
scripts/e2e.sh test         # xcodebuild test -testPlan E2E on "iPhone 16e"
scripts/e2e.sh down         # docker compose down -v
```

Needs Docker Desktop running and a clone of `twake-space-chat` (set `WEB_E2E` if it is not at
`~/Documents/Linagora/twake-space-chat/e2e`). Results: `build/e2e.xcresult` (screenshots kept for every test) and
`build/e2e.log`. `SIMULATOR_NAME` picks another simulator.

### What `up` does

1. `docker info`, then generates the Synapse config of `twake-space-chat/e2e` into its gitignored `.data/` folder
   (signing key, TLS certificate) and starts only `postgres mailpit dex ldap synapse` under the compose project
   `twake-ios-e2e`, so it does not clash with a web e2e stack. Twake on Matrix (ToM), side-service and Meet need local
   clones and are not started.
2. Removes `oidc_providers` from the copied `homeserver.yaml`. With no SSO the app takes its password route
   (ADR 0021), so XCUITest signs in without the system web-authentication sheet.
3. Checks `GET /_matrix/client/versions` lists `org.matrix.simplified_msc3575` (sliding sync, ADR 0003); stops if
   not. Probes ToM on `:3001` and only reports it.
4. Registers the admin `e2eadmin` with `register_new_matrix_user`, then with the admin API the users `ios-alice`
   (display name "Alice E2E") and `ios-bob`, password `password`.
5. Seeds, as ios-bob: room "E2E Chat" with "Hello from Bob", room "E2E History" with 300 messages
   ("History 1"…"History 300"); both users joined. Rooms are unencrypted.

### Staging fallback (ADR 0020)

When Docker is not available: `scripts/e2e.sh staging` sources `~/.factos/secrets/twake-chat-ios-staging.env`
(`MATRIX_HOMESERVER`, `MATRIX_USER`, `MATRIX_PASSWORD`; never printed), checks sliding sync and runs the plan.
Staging needs its own seeded rooms ("E2E Chat", "E2E History") and `E2E_DISPLAY_NAME`; on 2026-11-17 the staging
password login answered `403 M_FORBIDDEN`, so this path is not usable yet.

## Harness

- **Launch environment** (`TwakeChat/E2EHarness.swift`, Debug only): `IS_RUNNING_E2E_TESTS=1`,
  `E2E_RESET_SESSION=1` deletes the saved session and the SDK store before launch, `E2E_HOMESERVER` fills the
  homeserver field.
- **Test configuration** (`Tests/TwakeChatUITests/E2EApp.swift`): `E2E_HOMESERVER`, `E2E_USER`, `E2E_PASSWORD`,
  `E2E_PEER`, `E2E_DISPLAY_NAME`, passed as `TEST_RUNNER_E2E_*` by `scripts/e2e.sh` (the prefix is stripped,
  ADR 0020). Defaults match the seeded local stack.
- **Accessibility identifiers**: `Packages/DesignSystem/Sources/DesignSystem/Accessibility/A11yIdentifiers.swift`,
  used by the screens and by the tests (the UI test target links `DesignSystem`).

## Flows

| Flow | Test | Checks | Status 2026-11-17 |
|---|---|---|---|
| 1 | `AuthenticationFlowTests` | welcome → company server → password → chat list → logout | pass |
| 4 | `MessagingFlowTests` | send, reply, edit, quick reaction, delete in "E2E Chat" | pass |
| 3 | `PaginationFlowTests` | idle on "E2E History" stays at the bottom; one scroll up keeps the message on screen | expected failure (#80): the scroll position moves |
| 10 | `ProfileFlowTests` | Settings shows "Alice E2E" | pass on the local stack (#82 did not reproduce here) |
| 2 | `ScaffoldFlowTests.testEncryptedGroupMessageDecrypts` | encrypted group message decrypts (#79) | skipped: scaffold |
| media | `ScaffoldFlowTests.testSendAndReceiveImage` | image send and receive | skipped: scaffold |

`PaginationFlowTests` wraps its checks in `XCTExpectFailure(strict: false)`; remove the wrapper when #80 is fixed.

### Next

- Flow 2: start a crypto-capable second client from `twake-space-chat/e2e` (`bob-*.mjs`,
  `scripts/seed-encryption.mjs`) and cross-sign it, then bootstrap recovery on iOS (#79, #81). Needs ToM for the
  recovery words.
- Media: seed an `m.image` from ios-bob, add photos to the simulator library.
- CI: a macOS job running `scripts/e2e.sh all` and uploading `build/e2e.xcresult`.

## Borrowed from element-x-ios

Patterns only, no code (ADR 0016):
- A separate test target and test plan for tests that need a real server (`IntegrationTests` +
  `IntegrationTests.xctestplan`), kept out of the default plan.
- A launch environment flag the app reads to prepare for UI tests (`IS_RUNNING_INTEGRATION_TESTS`), here
  `IS_RUNNING_E2E_TESTS` plus a session reset.
- Server and credentials from environment variables (`INTEGRATION_TESTS_HOST/USERNAME/PASSWORD`).
- One shared `A11yIdentifiers` list used by both the app and the tests, one namespace per screen.
- A user-flow test that signs in, uses a room and logs out (`UserFlowTests`).
- `diagnosticCollectionPolicy: Always` in the plan, and a result bundle kept for CI upload.

Not borrowed: element-x-ios's mock-client `UITestsAppCoordinator` screens and snapshot tests (no mock layer here yet),
and its `swift run tools ci` runner.
