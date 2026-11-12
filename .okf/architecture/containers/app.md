---
type: Container
title: "App"
description: "C4 level 2 - the main iOS application: targets, modules, entry point and what it talks to."
tags: [c4, container, ios]
status: draft
---
# App

> Partly built. The `TwakeChat` app target (an empty root view) and the `Domain`, `AppShared`, `DesignSystem` and
> `MatrixData` packages exist (TWAK-34). The app target has the App Group `group.app.twake.ios.chat` and the Keychain
> access group `$(AppIdentifierPrefix)app.twake.ios.chat` in `TwakeChat/TwakeChat.entitlements` (TWAK-63). The
> Notification Service Extension, the `Features/` packages, the composition root, the coordinators and the `.xcconfig`
> files are still planned.

| | |
|---|---|
| Kind | Native iOS app, Swift, SwiftUI |
| Bundle id | `app.twake.ios.chat` |
| Deployment target | iOS 18.0 ([ADR 0002](../../adr/0002-ios-18-minimum-ios-26-styling.md)) |
| Entry point | `TwakeChat/TwakeChatApp.swift`: builds the composition root and the root coordinator |
| Talks to | [Backend](backend.md) through the Matrix SDK only |
| Shares with | The [Notification Service Extension](notification-service-extension.md), through one App Group container and one Keychain access group |

## Planned repository layout
```
TwakeChat/                  app target: App entry, composition root, coordinators
NotificationService/        extension target
Packages/
  DesignSystem/             colours, typography, components, iOS 18 / 26 styling
  Domain/                   models, repository protocols, use cases
  MatrixData/               the only module that imports the Matrix SDK
  AppShared/                App Group paths, Keychain, logging, build configuration
  Features/
    Authentication/
    ChatList/
    Room/
    Encryption/
    Settings/
```
Module rules are in [Components](../components/index.md); the reasoning is [ADR 0005](../../adr/0005-layered-local-swift-packages.md).

## Configuration
The Flutter app reads a bundled `config.json` (default homeserver, registration URL, privacy URL, support links). This
app keeps the same values in per-environment `.xcconfig` files read through `AppShared`. Server-side settings come
from the homeserver's discovery document at run time, not from the build.

## Identifiers
The app reuses the Flutter app's identifiers and therefore installs over it
([ADR 0012](../../adr/0012-reuse-flutter-bundle-identifier.md)).

| What | Value |
|---|---|
| App | `app.twake.ios.chat` |
| Notification Service Extension | `app.twake.ios.chat.nse` |
| App Group | `group.app.twake.ios.chat` |
| Keychain access group | `$(AppIdentifierPrefix)app.twake.ios.chat` |
| URL schemes | `twake.chat`, `matrix` |

## First launch after replacing the Flutter app
The app signs the Flutter app's old session out, then deletes its leftover files and Keychain items. The user signs in
again. Details in [ADR 0012](../../adr/0012-reuse-flutter-bundle-identifier.md).
