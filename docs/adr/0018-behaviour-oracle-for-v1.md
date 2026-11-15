---
type: ADR
title: "ADR 0018: Prove v1 behaviour with unit, snapshot and manual checks"
description: "Proposed: each v1 area names its oracle; unit and snapshot tests gate every pull request, a manual QA script gates each TestFlight build, and no end-to-end suite is required in CI for v1."
tags: [adr, testing, migration]
status: draft
---
# ADR 0018: Prove v1 behaviour with unit, snapshot and manual checks

**Status:** Proposed. The project owner answered "Approved" on card TWAK-5 (2026-11-11). The baseline reference run
below uses the commit pinned by [ADR 0013](0013-flutter-baseline-and-feature-status.md), which is still Proposed, so
this ADR becomes Accepted when the owner accepts ADR 0013 (or when it is updated to the baseline the owner picks).

## Context
The migration needs an oracle per slice: something that shows the native app behaves like the Flutter app did.
Inventory open questions 9, 10 and 12 ask what that oracle is, whether it runs on iOS in CI, whether `test/architecture`
is committed in the old repo, and whether the chat-room split is acceptable.

Facts this decision rests on:
- The target is a native Swift app ([ADR 0003](0003-matrix-rust-sdk.md), [ADR 0004](0004-swiftui-observable-coordinators.md)).
  The Flutter app's Patrol scenarios (`integration_test/scenarios/`) are Dart robots over the Flutter widget tree. They
  cannot drive the native app. They can serve only as a reference run on the Flutter app and as the step list for new
  tests or manual scripts.
- Patrol runs in the old repo's `.github/workflows/integration-tests.yaml` on an Android emulator, nightly (`schedule`,
  line 17) and on manual dispatch. No iOS job exists, although `pubspec.yaml` declares the Patrol iOS target
  (`bundle_id: app.twake.ios.chat`).
- The only login scenario signs in by API with a password (`login_scenario.dart`, `loginViaApi`). No scenario covers SSO,
  session verification or push. The local harness skips backend-dependent tests (`integration_test/base/test_base.dart`).
- [ADR 0010](0010-testing-strategy-two-ios-versions.md) puts integration tests against a real homeserver out of scope
  until a test server exists, and also says proxies "are covered by integration tests". The old repo already has a
  disposable Synapse harness (`scripts/integration-server-synapse.sh`), which is ADR 0010's own trigger to revisit.
- [ADR 0011](0011-v1-scope-core-chat.md) limits v1 to five areas, so an oracle is needed only for those.
  [ADR 0012](0012-reuse-flutter-bundle-identifier.md) makes users sign in again, so "unchanged" means the user-visible
  flow, not stored data.

## Decision
**Oracle per v1 area.**

| v1 area (ADR 0011) | Flutter oracle today | Oracle for the native app | Runs where | CI requirement |
|---|---|---|---|---|
| Sign-in: server discovery, SSO sign-in, sign-out | `login_scenario.dart`, password login by API. No SSO test. | Unit tests with fakes for discovery and the SSO token step. Manual QA script for SSO sign-in and sign-out against staging. | CI; device before each TestFlight build | Unit tests gate every pull request |
| Chat list: rooms ordered by activity, unread state, invitations | `chat_list_scenarios.dart` | View-model unit tests with fakes for ordering by activity, unread state and accepting or declining an invitation. Snapshot tests of list cells, including the unread and invitation states. Manual script derived from the Patrol steps. | CI; device before each build | Unit and snapshot tests gate every pull request |
| Timeline: text, images, video and files; replies; reactions; edits and deletions shown; read state; send and retry | `chat_scenario.dart`, `send_message_scenario.dart`, `message_reactions_scenario.dart`, `chat_image_retry_scenario.dart` (`requiresHardware: true`) | View-model unit tests with fakes for each item kind, replies, reactions, edited and deleted items, read state, and the send state machine including retry. Snapshot tests of the timeline cells for each of those kinds. Manual script for media upload and for retry after going offline. | CI; device before each build | Unit and snapshot tests gate every pull request |
| Encryption: encrypted rooms, recovery with the recovery key, verifying this session from another one | `settings_recovery_key_scenario.dart` (mobile only). No verification scenario. | Mapper unit tests with fixtures, including the encrypted-room and undecryptable-event states. Manual: send and read in an encrypted room, restore with the recovery key, verify this session from another client. | CI; device before each build | Unit tests gate every pull request |
| Push: notifications with decrypted text | No Patrol scenario. Unit tests `test/utils/push_*`. | Unit tests of the extension's payload handling with fakes. Manual push matrix on a device: locked device, encrypted room. ADR 0012 first-launch cleanup: one unit test, plus a manual check on a device that had the Flutter app. | CI; device before each build | Unit tests gate every pull request |

Manual checks run on iOS 26 only. The project owner decided on 2026-11-12 that no step needs an iOS 18 runtime;
compiling against the iOS 18.0 deployment target is enough ([Build](../../.okf/workflows/build.md)).

**Baseline.** One recorded run of the Patrol scenarios above on the Flutter app, at the commit pinned by
[ADR 0013](0013-flutter-baseline-and-feature-status.md), is the reference for the manual scripts. It runs on an iOS
simulator, except `chat_image_retry_scenario.dart`: its test is marked `requiresHardware: true`
(`chat_image_retry_test.dart`) and is skipped by the local harness (`test_base.dart`), so that scenario is recorded on a
physical device. Doing that run is inventory slice 3, not this decision.

**CI requirement.** Unit and snapshot tests gate every pull request, as ADR 0010 says. No end-to-end suite has to run on
iOS in CI for v1. The manual QA script gates each TestFlight build. ADR 0010's out-of-scope line for integration tests
stays as written. The opt-in local integration tests against the staging homeserver, which the project owner decided on
2026-11-12, stand: they run on a developer machine, not in CI, and skip when the credentials are absent.

**Proxy coverage.** While this record is Proposed, the clause of ADR 0010 that says proxies "are covered by integration
tests" stays binding. Once the owner accepts this record, it replaces that clause: until an end-to-end suite exists,
the `MatrixData` proxies are covered by the manual QA script and the opt-in local integration tests, not by a CI
integration suite. ADR 0010 itself is not edited, as [ADR 0001](0001-record-architecture-decisions.md) requires.

**`test/architecture` in the old repo.** Not committed for this project. It is local-only by design in the old repo
(`docs/adoption-plan.md`, section 12, lists it in `.git/info/exclude`). The native repo enforces layering with package
dependencies ([ADR 0005](0005-layered-local-swift-packages.md)), so a Dart baseline does not protect it. Committing it
remains the Flutter team's decision.

**Chat-room split.** The read and write split of inventory slices 14 and 15 is acceptable if each card names its oracle
from the timeline row above. The write side is still too large for one review. It is cut along ADR 0011's timeline
list: send and retry; media (images, video, files); reactions and replies; edits and deletions shown; read state. Chat
details, profiles and pinned messages are not in v1 (ADR 0011) and leave slice 15.

## Consequences
**Good.** Every v1 area has a named oracle now, without building a harness first. CI stays fast and deterministic.
**Costly.** SSO, verification, push and offline retry rely on people, before each build. A regression in those areas
can reach a pull request unseen and is caught only at the build gate. The manual script must be written and kept in step
with the app. **Alternatives rejected.** Reusing Patrol as the oracle: it cannot drive a native app. A native
end-to-end suite in CI for v1: would need a test homeserver in CI and a new ADR superseding ADR 0010's out-of-scope line; possible, but
it is the harness work of inventory slice 2, and it still would not cover SSO or a second verifying client. Manual QA
only: leaves logic untested, against the project rule that every change in behaviour comes with a test.

## When to revisit
When the disposable Synapse harness runs in this repo's CI; then ADR 0010 is revisited and the manual rows that a native
end-to-end suite can cover move to CI. Also when a regression reaches testers that the manual script missed.
