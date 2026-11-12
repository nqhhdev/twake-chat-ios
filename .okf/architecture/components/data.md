---
type: Component
title: "Data Layer"
description: "C4 level 3 - the only module that imports the Matrix SDK; implements the Domain repository protocols."
tags: [c4, component, data, matrix]
status: draft
---
# Data Layer

| | |
|---|---|
| Folder | `Packages/MatrixData/` (the package exists and imports the SDK; no proxy yet) |
| Holds | Proxies around SDK objects, repository implementations, mappers from SDK types to Domain models |
| May import | [Domain](domain.md), `AppShared`, the Matrix SDK |
| Must not import | [Features](ui.md), [Design System](design-system.md) |

## Proxies
Each long-lived SDK object is wrapped once, behind a protocol, so the rest of the app never sees an SDK type
([ADR 0006](../../adr/0006-sdk-behind-proxy-protocols.md)).

| Proxy | Wraps | Responsibility |
|---|---|---|
| `ClientProxy` | the SDK client | Session restore, sync start and stop, sign-out, pusher registration |
| `RoomListProxy` | the SDK room list | The ordered list of rooms as a stream of Domain `RoomSummary` values |
| `RoomProxy` | one room | Send, reply, react, mark as read, room state |
| `TimelineProxy` | one room's timeline | Applies the SDK's incremental updates and publishes `[TimelineItem]`; pagination |
| `EncryptionProxy` | the SDK encryption API | Recovery state, entering a recovery key, session verification |
| `NotificationProxy` | the SDK notification client | Fetch and decrypt one event for the [Notification Service Extension](../containers/notification-service-extension.md) |

SDK class and method names are not written here on purpose: they change between releases and must be read from the
pinned version when the code is written. For the pinned version they are in
[Matrix SDK 26.04.01 API](../../references/matrix-sdk-26-04-01-api.md).

## Errors and threading
- SDK errors are caught in this layer and rethrown as Domain errors. No SDK error type crosses the boundary.
- SDK callbacks arrive on background threads. Proxies turn them into `AsyncStream` values; view models hop to the main
  actor themselves.

## Storage
The SDK's own store (state, event cache, crypto) is the only database in v1. It lives in the App Group container
([ADR 0007](../../adr/0007-shared-session-store-app-group.md)). Tokens live in the Keychain, through `AppShared`.
