# twake-chat-ios

## Target architecture

Each line names the record that owns it and the owner answer behind it. "Open" means no owner answer settles it yet.

### Stack and platforms
- Native Swift 6 / SwiftUI app for iPhone; deployment target iOS 18, built with the iOS 26 SDK or a newer one; iOS 26
  styling only inside `DesignSystem`. [ADR 0002](.okf/adr/0002-ios-18-minimum-ios-26-styling.md),
  [ADR 0004](.okf/adr/0004-swiftui-observable-coordinators.md). Owner: card TWAK-1, "Approved".
- Android, web and desktop are not built here. Whether they stay in twake-on-matrix, and whether that app (and its iOS
  build) is frozen, maintained in parallel or retired: **open** (TWAK-1 question 3 had no proposal).

### Matrix SDK
- Matrix Rust SDK through `matrix-rust-components-swift`, pinned to an exact version (26.04.01), imported only by
  `MatrixData`. The homeserver must support sliding sync. [ADR 0003](.okf/adr/0003-matrix-rust-sdk.md),
  [ADR 0015](.okf/adr/0015-pin-matrix-rust-components-swift-26-04-01.md). Owner: TWAK-1, "Approved".

### Layer rules
- Layers are local Swift packages (`Features`, `Domain`, `MatrixData`, `DesignSystem`, `AppShared`); allowed imports
  are package dependencies, so a wrong import does not compile. [ADR 0005](.okf/adr/0005-layered-local-swift-packages.md).
  Owner: TWAK-1, "Approved" (confirms ADRs 0002 to 0005).
- No SDK type leaves `MatrixData`; it wraps each SDK object in a proxy that implements a `Domain` protocol.
  [ADR 0006](.okf/adr/0006-sdk-behind-proxy-protocols.md). Owner: accepted as written (`.okf/log.md`, ADRs 0001 and
  0004 to 0010).
- One `@MainActor @Observable` view model per screen; coordinators own navigation.
  [ADR 0004](.okf/adr/0004-swiftui-observable-coordinators.md). Owner: TWAK-1, "Approved".
- This repository keeps its own ADRs. The Flutter repo's ADRs 37, 38 and 39 are reference only; an idea from them
  enters as a new ADR here. [ADR 0001](.okf/adr/0001-record-architecture-decisions.md). Owner: TWAK-1 question 4,
  "Approved".

### Licence
- `LICENSE` is MIT today. Whether to relicense to AGPL-3.0 and port with attribution, or stay MIT and reimplement
  clean-room (reusing only the Apache-2.0 Element X snapshot at `42746d711`), is **open**: the owner approved the
  proposal (TWAK-2) but has not picked an option or confirmed the copyright holder. Until then, nothing is copied,
  translated or ported from twake-on-matrix, element-ios or Element X.
  [ADR 0016](.okf/adr/0016-source-licence-and-reuse-rule.md). Owner: TWAK-2, "Approved"; option and copyright holder
  **open**.

### Data compatibility
- The app installs over the Flutter app as `app.twake.ios.chat`. Users sign in again; the Flutter session and keys are
  not reused; a first-launch cleanup deletes the Flutter app's leftovers, including its stored recovery-key items.
  [ADR 0012](.okf/adr/0012-reuse-flutter-bundle-identifier.md). Owner: accepted with its cleanup and release rule
  (`.okf/log.md`). How the cleanup removes the Flutter app's own device and pusher is **open**
  ([ADR 0017](.okf/adr/0017-flutter-upgrade-keep-and-drop-lists.md) open point 1).
- Kept unchanged: bundle and extension ids, App Group `group.app.twake.ios.chat`, Keychain group
  `KUT463DS29.app.twake.ios.chat`, URL schemes, associated domains, push app ids, the pusher fields and push payload
  keys (`event_id_only`), and every ToM backend path. The cleanup deletes the stores listed in ADR 0017. Owner: TWAK-3,
  "Approved" on the lists; ADR 0017 stays **Proposed** until its open points are settled, so no cleanup code is
  written yet.
- **Open** (ADR 0017 open points): which device the cleanup signs out, how updating users recover encryption, the
  signing team, and the name of the new SDK store directory.

### Scope
- Version 1 is sign-in, chat list, timeline, encryption recovery and push; every other Flutter feature is deferred.
  [ADR 0011](.okf/adr/0011-v1-scope-core-chat.md). Owner: accepted (`.okf/log.md`, "All twelve ADRs are accepted").
- Status of each Flutter feature (kept, deferred, proposed for dropping):
  [ADR 0013](.okf/adr/0013-flutter-baseline-and-feature-status.md), **Proposed**. Owner answer: **open** (none
  recorded on TWAK-4).

### Baseline and oracle
- Baseline: [ADR 0013](.okf/adr/0013-flutter-baseline-and-feature-status.md) *proposes* porting behaviour from
  twake-on-matrix `5a3e9e84920078d3d0fb5148146a179c1a06c04a` on `origin/main` (2026-11-10). This is not a decided
  baseline: the owner has not answered on card TWAK-4, and no rule in
  [Constraints](.okf/engineering/constraints.md) rests on it yet. It is tracked in
  [Open Verifications](.okf/backlog/open-verifications.md).
- Oracle: per v1 area, unit and snapshot tests gate every pull request, and a manual QA script on iOS 26 gates each
  TestFlight build; no step needs an iOS 18 runtime (owner decision, 2026-11-12). One recorded Patrol run of the Flutter
  app at the baseline is the reference for the manual scripts. No end-to-end suite is required in CI for v1.
  [ADR 0018](.okf/adr/0018-behaviour-oracle-for-v1.md). Owner: TWAK-5, "Approved"; ADR 0018 stays **Proposed** until
  ADR 0013 fixes the baseline its reference run uses. Until then, ADR 0010 stays the binding testing rule.

## Documentation

All knowledge lives in [`.okf/`](.okf/index.md). Start with:

- [System Context](.okf/architecture/context.md) - what the app is and what it depends on
- [Components](.okf/architecture/components/index.md) - the modules and their import rules
- [Architecture Decision Records](.okf/adr/index.md) - why each choice was made
- [Constraints](.okf/engineering/constraints.md) - the rules code must keep
- [Backlog](.okf/backlog/index.md) - open decisions, unverified assumptions, deferred features

Check the knowledge base after editing it:

```bash
python3 .okf/tools/okf.py --check
```
