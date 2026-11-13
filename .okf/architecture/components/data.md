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
| Folder | `Packages/MatrixData/`: `Proxies/ClientProxy.swift`, `Repositories/MatrixAuthenticationRepository.swift`, `Mappers/UserSessionMapper.swift` (TWAK-64), `MatrixPlatform.swift` (TWAK-67) |
| Folder | `Packages/MatrixData/`: `Proxies/ClientProxy.swift`, `Repositories/MatrixAuthenticationRepository.swift`, `Mappers/UserSessionMapper.swift` (TWAK-64); `Proxies/RoomListProxy.swift`, `Proxies/ListDiff.swift`, `Mappers/RoomSummaryMapper.swift` (TWAK-66) |
| Holds | Proxies around SDK objects, repository implementations, mappers from SDK types to Domain models |
| May import | [Domain](domain.md), `AppShared`, the Matrix SDK |
| Must not import | [Features](ui.md), [Design System](design-system.md) |

## Proxies
Each long-lived SDK object is wrapped once, behind a protocol, so the rest of the app never sees an SDK type
([ADR 0006](../../adr/0006-sdk-behind-proxy-protocols.md)).

| Proxy | Wraps | Responsibility |
|---|---|---|
| `ClientProxy` | the SDK client | **Implemented (TWAK-64):** password login, session restore and sign-out. **TWAK-66:** sync start and stop; sign-out stops sync first. Later: pusher registration |
| `RoomListProxy` | the SDK room list | **Implemented (TWAK-66):** the joined rooms, in the SDK's order, as a stream of Domain `RoomSummary` values |
| `RoomProxy` | one room | Send, reply, react, mark as read, room state |
| `TimelineProxy` | one room's timeline | Applies the SDK's incremental updates and publishes `[TimelineItem]`; pagination |
| `EncryptionProxy` | the SDK encryption API | Recovery state, entering a recovery key, session verification |
| `NotificationProxy` | the SDK notification client | Fetch and decrypt one event for the [Notification Service Extension](../containers/notification-service-extension.md) |

**What exists (TWAK-64).** `ClientProxy` is a `final class` with no public SDK member. It builds the client with
`sessionPaths` under an injected store directory (`data/` and `cache/`), `discoverNative` sliding sync and the
`multiProcess` cross-process lock. The pinned SDK refuses that lock without a session delegate, so
`KeychainClientSessionDelegate` gives the SDK the saved session and saves refreshed tokens with
`KeychainSessionStore.saveRefreshedTokens`, which only updates the item of the same user and device and never adds
one: a refresh after sign-out cannot bring the session back. `MatrixAuthenticationRepository` (an actor) implements
the Domain `AuthenticationRepository` with the Flutter sign-in of [ADR 0021](../../adr/0021-sign-in-as-the-flutter-app.md):
`HomeserverDiscovery` reads `.well-known`, the login flows with their identity providers and a registration probe over
plain HTTP (the pinned SDK lists no providers); `startSSOLogin` builds a client and keeps the SDK `SsoHandler` until
`finishSSOLogin` hands it the web session's callback (`loginToken`); password login is the same in every build. The
store holds one session, so sign-in is refused (`unknown`) while a session is saved or a client runs, and a restore keeps the running client. It saves
the session, including its sliding sync version, in `KeychainSessionStore` and exposes the signed-in `clientProxy` for
later cards. `logout()` first restores a client when none runs yet (cold launch), so the server still signs the device
out; it deletes the store directory and the Keychain item even when the server call fails, then reports that failure. `UserSessionMapper` is internal: it maps `M_FORBIDDEN` to `invalidCredentials`,
connection failures and an unreachable server to `serverUnreachable`, a bad server name or well-known to
`invalidHomeserverURL`, and everything else to `unknown`. The app's composition root wires it (TWAK-65).

**What exists (TWAK-66).** `RoomListProxy` (an actor) implements the Domain `RoomListRepository`. `start()` asks the
authentication repository for the signed-in `ClientProxy` (`notSignedIn` without one), which starts the client's sync
service once and shares it; it then subscribes to all rooms through the dynamic adapters with one page of 200 and the
joined filter, keeping the entries task handle alive. The SDK listener only queues each batch of updates; one task
applies them in order. Each update is turned into the generic `ListDiff<Element>` (the eleven cases of the SDK's list
update), only the rooms it carries are mapped to `RoomSummary` (`RoomSummaryMapper`: display name or else the room
id; the body of a message as text, `nil` for other events; the sender's display name or else their Matrix id; the
millisecond timestamp as a date), and the diff is applied to the published list, which is never re-sorted.
The SDK room list, its controller and the entries task handle are kept by the `ClientProxy`
(`keepWhileSyncing`), which cancels and releases them whenever sync stops: the SDK aborts the process when a room list
is freed after its client, so they must never outlive it, and the applying task holds the client until it ends.
`stop()` ends the subscription and stops sync. `ClientProxy.logout()` stops sync for good (a `start()` after it
fails, so no sync service is built while the store is removed), and so releases the room list, before the server
sign-out, so nothing writes to the store while `MatrixAuthenticationRepository` deletes it, also
when the chat list calls `stop()` only after logout. Nothing here logs: the summaries hold
message content ([ADR 0009](../../adr/0009-push-gateway-and-nse-decryption.md)). `ListDiff` and the mapper are tested
in `MatrixDataTests`; the mapper fixtures are enum cases only, because the SDK's struct initializers are in a binary
that bundle does not link. The message-text path (a message's body and sender) has no automated test: the opt-in
staging test `RoomListIntegrationTests` checks only that a non-empty list of rooms with ids and names arrives, and the
text is checked by hand on the simulator (a message sent from a second account updates the row).

## Platform
`MatrixPlatform.setUp()` (`MatrixPlatform.swift`, TWAK-67) sets up the SDK's runtime and logs. It is the first call in
`TwakeChatApp.init`, before any client is built; without it a password login reached the server but never returned.
It reaches the SDK once per process (a lazily set `static let`), never throws and logs nothing of its own; later calls
do nothing. Debug: level info, written to stdout and the system log. Release: level warn, written nowhere. No trace log
packs, no log files, no Sentry. The app uses the full tokio runtime; the
[Notification Service Extension](../containers/notification-service-extension.md) will use the lightweight one when it
is built.

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

`AppShared` holds the storage pieces that need no SDK (TWAK-63):
- `KeychainSessionStore` (`Sources/AppShared/KeychainSessionStore.swift`) saves, loads and deletes one `StoredSession`
  (user id, device id, homeserver URL, tokens; no recovery key) as a generic-password item, given a service name and
  the Keychain access group. The item is readable after first unlock, this device only, so the extension can read it
  while the device is locked. Errors carry only the `OSStatus`; nothing is logged. `save` is for a sign-in and may
  add the item. Token refresh is not here yet: the card that needs it adds it.
- `AppGroupContainer` (`Sources/AppShared/AppGroupContainer.swift`) names the SDK store directory in the App Group
  container: one fixed directory, `Library/Application Support/TwakeChat/SDK`, that no caller can change, so the app
  and the extension open the same store. It is the name
  [ADR 0017](../../adr/0017-flutter-upgrade-keep-and-drop-lists.md) open point 4 proposes, pending the owner's
  confirmation. A test checks it is apart from the Flutter app's trees that the cleanup deletes. It creates and deletes
  nothing.

`AppShared` does not import Domain ([ADR 0005](../../adr/0005-layered-local-swift-packages.md)), so MatrixData will map
`StoredSession` to Domain `UserSession` when it implements `AuthenticationRepository` (a later card). The app reads its
expanded Keychain group from the `KeychainAccessGroup` key of `TwakeChat/Info.plist`.
