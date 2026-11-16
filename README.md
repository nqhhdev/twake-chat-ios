# Twake Chat for iOS

Native iOS client for Twake Chat, built on [Matrix](https://matrix.org), in Swift 6 and SwiftUI. It replaces the iOS
build of the Flutter app and installs over it with the same bundle identifier.

**Status:** in development. Internal and TestFlight builds only; no App Store release until the project owner accepts
the feature gap with the Flutter app ([ADR 0012](docs/adr/0012-reuse-flutter-bundle-identifier.md)).

## Requirements

- Xcode 26 or newer (iOS 26 SDK), with an iOS 26 simulator
- Deployment target: iOS 18 ([ADR 0002](docs/adr/0002-ios-18-minimum-ios-26-styling.md))
- A Matrix homeserver with sliding sync ([ADR 0003](docs/adr/0003-matrix-rust-sdk.md))

## Getting started

Run every command from the repository root. Swift Package Manager resolves the dependencies on the first build.

| Task | Command |
|---|---|
| Open in Xcode | `open TwakeChat.xcodeproj`, scheme `TwakeChat` |
| Build | `xcodebuild build -project TwakeChat.xcodeproj -scheme TwakeChat -destination 'generic/platform=iOS Simulator'` |
| Test (architecture check, package tests, simulator tests) | `scripts/test.sh` |
| Test on another simulator | `SIMULATOR_NAME='iPhone 17 Pro' scripts/test.sh` |
| Lint | `scripts/lint.sh` |
| Format | `scripts/lint.sh --fix` |
| Architecture rules only | `scripts/check-architecture.sh` |

A build passes when it ends with `** BUILD SUCCEEDED **` and has no warning. Details and edge cases:
[Build](.okf/workflows/build.md), [Test](.okf/workflows/test.md). Tests against the staging server are opt-in and
local only ([ADR 0020](docs/adr/0020-opt-in-local-staging-integration-tests.md)).

## Architecture

A layered clean architecture. Each layer is a local Swift package, so a forbidden import does not compile
([ADR 0005](docs/adr/0005-layered-local-swift-packages.md)).

```
Features  ->  Domain  <-  MatrixData  ->  Matrix Rust SDK
   |                          |
   v                          v
DesignSystem               AppShared

TwakeChat (app), TwakeChatNSE, TwakeChatShare: composition roots; they build the objects and join the features.
```

| Module | Holds | May import |
|---|---|---|
| `Packages/Domain` | Models, repository protocols, formatting. No SwiftUI, no SDK | Foundation |
| `Packages/MatrixData` | The only code that imports the Matrix SDK: proxies, mappers, repositories | Domain, AppShared, SDK |
| `Packages/Features/*` | One package per feature: screens and view models | Domain, DesignSystem |
| `Packages/DesignSystem` | Colours, typography, layout, shared components; the only place that checks the iOS version | SwiftUI |
| `Packages/AppShared` | What the app and its extensions share: App Group container, Keychain session store | Foundation |

State management is Apple's Observation framework: one `@MainActor @Observable` view model per screen, fed by
`AsyncStream`s from the repositories. There is no third-party state library. Data flows one way:

```
Matrix SDK -> proxy (MatrixData) -> AsyncStream of Domain models -> view model -> SwiftUI view
```

## Patterns

| Pattern | Where | Rule |
|---|---|---|
| MVVM with Observation | Every screen | The view model holds the state and the logic; the view only reads and calls ([ADR 0004](docs/adr/0004-swiftui-observable-coordinators.md)) |
| Coordinator | `AuthenticationCoordinator`, `ChatShell` | Navigation lives outside the screens; a feature never imports another feature. The app target joins them with closures |
| Repository | `Domain/Repositories` | A feature sees only a `Domain` protocol; `MatrixData` implements it |
| Proxy over the SDK | `MatrixData/Proxies` | Each SDK object is wrapped; no SDK type leaves `MatrixData` ([ADR 0006](docs/adr/0006-sdk-behind-proxy-protocols.md)) |
| Mapper | `MatrixData/Mappers` | Static functions turn SDK values into `Domain` models |
| Composition root | `TwakeChatApp`, `RootView` | Dependencies are passed in initialisers. No service locator, no singleton for app state |
| Diff stream | `ListDiff`, `RoomListProxy`, `TimelineProxy` | SDK list updates are queued and applied in order by one task; lists are never re-sorted |
| Structured concurrency | Everywhere | `async`/`await`, actors and `Sendable` under Swift 6 strict concurrency; no completion handlers |
| Test doubles per feature | `*TestSupport` targets | Each feature ships fakes of the repositories it uses |

## Practices

- **Small view models, pure helpers.** A rule that can be a static function is one (`TimelineRows`,
  `HistoryLoading`), so it is tested without a screen.
- **Every change in behaviour comes with a test**, written with Swift Testing.
- **Architecture is checked by a script**, not only by review: `scripts/check-architecture.sh`.
- **One style:** swift-format defaults ([ADR 0014](docs/adr/0014-ci-github-actions-swift-format.md)); the build has
  no warnings.
- **SDK objects never outlive their client.** `ClientProxy` keeps them while sync runs and waits for their tasks to
  end before it releases them.
- **Secrets only in the Keychain; logs and push payloads carry no message content**
  ([ADR 0007](docs/adr/0007-shared-session-store-app-group.md),
  [ADR 0009](docs/adr/0009-push-gateway-and-nse-decryption.md)).
- **The SDK is pinned to an exact version**; an upgrade is its own pull request
  ([ADR 0015](docs/adr/0015-pin-matrix-rust-components-swift-26-04-01.md)).
- **A decision changes through an ADR first**, then the code.

The full rule list, with what enforces each rule, is in [Constraints](.okf/engineering/constraints.md).

## Project structure

```
TwakeChat/            App target: wiring, navigation shell, push, links, sharing
TwakeChatNSE/         Notification Service Extension: decrypts a push before it shows
TwakeChatShare/       Share extension
Packages/
  Domain/             Models and repository protocols
  MatrixData/         Matrix SDK access
  DesignSystem/       Colours, typography, components
  AppShared/          Code shared by the app and its extensions
  Features/           Authentication, ChatList, Room, People, Settings
Tests/                App-level, MatrixData and acceptance tests
scripts/              Test, lint and architecture checks
docs/adr/             Architecture Decision Records
.okf/                 Knowledge base
```

## Decisions

Every choice has a record in [docs/adr](docs/adr/index.md). The ones a newcomer meets first:

| Topic | Record |
|---|---|
| Platforms and iOS versions | [ADR 0002](docs/adr/0002-ios-18-minimum-ios-26-styling.md) |
| Matrix Rust SDK and its pin | [ADR 0003](docs/adr/0003-matrix-rust-sdk.md), [ADR 0015](docs/adr/0015-pin-matrix-rust-components-swift-26-04-01.md) |
| Layers and the SDK boundary | [ADR 0005](docs/adr/0005-layered-local-swift-packages.md), [ADR 0006](docs/adr/0006-sdk-behind-proxy-protocols.md) |
| Sign-in | [ADR 0008](docs/adr/0008-authentication-sso-and-discovery.md), [ADR 0021](docs/adr/0021-sign-in-as-the-flutter-app.md) |
| Push | [ADR 0009](docs/adr/0009-push-gateway-and-nse-decryption.md) |
| Testing | [ADR 0010](docs/adr/0010-testing-strategy-two-ios-versions.md), [ADR 0018](docs/adr/0018-behaviour-oracle-for-v1.md) |
| Scope and feature status | [ADR 0011](docs/adr/0011-v1-scope-core-chat.md), [ADR 0013](docs/adr/0013-flutter-baseline-and-feature-status.md), [ADR 0023](docs/adr/0023-features-from-web-client-ux-from-best-messengers.md) |
| Upgrade from the Flutter app | [ADR 0012](docs/adr/0012-reuse-flutter-bundle-identifier.md), [ADR 0017](docs/adr/0017-flutter-upgrade-keep-and-drop-lists.md) |
| Adaptive layout | [ADR 0022](docs/adr/0022-adaptive-layout-flutter-breakpoints.md) |

Decisions still open, unverified assumptions and deferred features are tracked in the
[Backlog](.okf/backlog/index.md).

## Documentation

All project knowledge lives in [`.okf/`](.okf/index.md):

- [System Context](.okf/architecture/context.md): what the app is and what it depends on
- [Components](.okf/architecture/components/index.md): the modules and their import rules
- [Constraints](.okf/engineering/constraints.md): the rules code must keep
- [Backlog](.okf/backlog/index.md): open decisions, unverified assumptions, deferred features

Check the knowledge base after editing it:

```bash
python3 .okf/tools/okf.py --check
```

## Licence

[MIT](LICENSE). Whether the project relicenses, and what may be reused from other clients, is an open decision
([ADR 0016](docs/adr/0016-source-licence-and-reuse-rule.md)); until it is settled, no code is copied or ported from
them.
