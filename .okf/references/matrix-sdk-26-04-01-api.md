---
type: Reference
title: "Matrix SDK 26.04.01 API"
description: "The exact matrix-rust-components-swift 26.04.01 names and signatures the login, room list, timeline and send cards need, each cited from the resolved checkout."
tags: [matrix, sdk, reference]
status: draft
---
# Matrix SDK 26.04.01 API

The names below come from `matrix-rust-components-swift` at tag `26.04.01`, revision
`2916f3f9cc2aea86ba3a820cb6a8389e13e0284a`, the version pinned by [ADR 0015](../adr/0015-pin-matrix-rust-components-swift-26-04-01.md).
They do not come from Element X or from memory. Write code against this page, or against the checkout itself. Do not
use Element X `main`: it follows newer releases.

**Where the checkout is.** Run `swift package resolve --package-path Packages/MatrixData`. The source is then in
`Packages/MatrixData/.build/checkouts/matrix-rust-components-swift/` (Xcode also puts a copy under its
`SourcePackages/checkouts/`). Every citation is `Sources/MatrixRustSDK/<file>:<line>` in that checkout. All the names
here are in `matrix_sdk_ffi.swift`, so the table gives only the line. After an SDK upgrade (its own pull request,
[ADR 0003](../adr/0003-matrix-rust-sdk.md)), the page must be checked again.

The page records names only. It decides nothing about which login flow ships (see
[ADR 0008](../adr/0008-authentication-sso-and-discovery.md)). The proxies that wrap these types come with the features
that need them ([ADR 0006](../adr/0006-sdk-behind-proxy-protocols.md), [ADR 0011](../adr/0011-v1-scope-core-chat.md)).

## Building a client: `ClientBuilder` (class at line 3609)

| What | Name and signature | Line |
|---|---|---|
| New builder | `ClientBuilder.init()` | 3648 |
| Server name or URL | `serverNameOrHomeserverUrl(serverNameOrUrl: String) -> ClientBuilder` | 3859 |
| Server name only | `serverName(serverName: String) -> ClientBuilder` | 3850 |
| Homeserver URL only | `homeserverUrl(url: String) -> ClientBuilder` | 3796 |
| Session paths | `sessionPaths(dataPath: String, cachePath: String) -> ClientBuilder` | 3876 |
| SQLite store, an alternative to session paths | `sqliteStore(config: SqliteStoreBuilder) -> ClientBuilder`; `SqliteStoreBuilder.init(dataPath: String, cachePath: String)` | 3907; 14240 |
| Sliding sync setting | `slidingSyncVersionBuilder(versionBuilder: SlidingSyncVersionBuilder) -> ClientBuilder` | 3895 |
| Sliding sync choices | `enum SlidingSyncVersionBuilder { case none, native, discoverNative }` | 37709-37713 |
| Cross-process store lock | `crossProcessLockConfig(crossProcessLockConfig: CrossProcessLockConfig) -> ClientBuilder` | 3731 |
| Lock choices | `enum CrossProcessLockConfig { case multiProcess(holderName: String), singleProcess }` | 27482, 27487, 27496 |
| Session delegate, for token refresh between processes | `setSessionDelegate(sessionDelegate: ClientSessionDelegate) -> ClientBuilder` | 3886 |
| `ClientSessionDelegate` | `retrieveSessionFromKeychain(userId: String) throws -> Session`, `saveSessionInKeychain(session: Session)` | 41032, 41034, 41036 |
| Build | `build() async throws -> Client` | 3714 |

## Login, session, restore and logout: `Client` (class at line 1457)

| What | Name and signature | Line |
|---|---|---|
| Password login | `login(username: String, password: String, initialDeviceName: String?, deviceId: String?) async throws` (returns nothing; read the session afterwards) | 2453 |
| Read the session | `session() throws -> Session` | 2894 |
| `Session` fields | `struct Session`: `accessToken: String`, `refreshToken: String?`, `userId: String`, `deviceId: String`, `homeserverUrl: String`, `oidcData: String?`, `slidingSyncVersion: SlidingSyncVersion` | 23246, 23250-23277 |
| Session's sliding sync value | `enum SlidingSyncVersion` | 37642 |
| Restore from a saved session | `restoreSession(session: Session) async throws` | 2758 |
| Restore, with room-loading settings | `restoreSessionWith(session: Session, roomLoadSettings: RoomLoadSettings) async throws`; `enum RoomLoadSettings` | 2780; 36301 |
| Logout | `logout() async throws` | 2513 |
| Server's sliding sync version | `Client.slidingSyncVersion() -> SlidingSyncVersion` | 3058 |
| Which login flows the server offers | `homeserverLoginDetails() async -> HomeserverLoginDetails`; on it (class at line 5149): `supportsPasswordLogin() -> Bool`, `supportsSsoLogin() -> Bool`, `slidingSyncVersion() -> SlidingSyncVersion` | 2243; 5239, 5250, 5205 |

## SSO login-token flow

| What | Name and signature | Line |
|---|---|---|
| Start SSO | `Client.startSsoLogin(redirectUrl: String, idpId: String?) async throws -> SsoHandler` | 3087 |
| URL to open in the browser | `SsoHandler.url() -> String` (class at line 14420) | 14498 |
| Finish with the callback URL | `SsoHandler.finish(callbackUrl: String) async throws` | 14476 |

## Sync and room list

| What | Name and signature | Line |
|---|---|---|
| Sync service builder | `Client.syncService() -> SyncServiceBuilder` | 3239 |
| Build the sync service | `SyncServiceBuilder.finish() async throws -> SyncService` (class at line 14769) | 14822 |
| Start, stop, state | `SyncService.start() async`, `stop() async`, `state(listener: SyncServiceStateObserver) -> TaskHandle` (class at line 14576; observer protocol at 45487) | 14662, 14689, 14680 |
| Room list service | `SyncService.roomListService() -> RoomListService` | 14654 |
| All rooms | `RoomListService.allRooms() async throws -> RoomList` (class at line 11094) | 11147 |
| One room | `RoomListService.room(roomId: String) throws -> Room` | 11164 |
| Service state | `RoomListService.state(listener: RoomListServiceStateListener) -> TaskHandle` (protocol at 43685) | 11173 |
| Entries | `RoomList.entriesWithDynamicAdapters(pageSize: UInt32, listener: RoomListEntriesListener) -> RoomListEntriesWithDynamicAdaptersResult` (class `RoomList` at line 10689) | 10742 |
| Entries result | `RoomListEntriesWithDynamicAdaptersResult.controller() -> RoomListDynamicEntriesController`, `entriesStream() -> TaskHandle` (class at line 10962) | 11015, 11023 |
| Paging and filters | `RoomListDynamicEntriesController.addOnePage()`, `resetToOnePage()`, `setFilter(kind: RoomListEntriesDynamicFilterKind) -> Bool` (class at line 10829) | 10882, 10889, 10896 |
| Listener | `protocol RoomListEntriesListener { func onUpdate(roomEntriesUpdate: [RoomListEntriesUpdate]) }` | 43437, 43439 |
| Diff type | `enum RoomListEntriesUpdate { append(values: [Room]), clear, pushFront(value: Room), pushBack(value: Room), popFront, popBack, insert(index: UInt32, value: Room), set(index: UInt32, value: Room), remove(index: UInt32), truncate(length: UInt32), reset(values: [Room]) }` | 35707-35726 |

## Timeline and sending

| What | Name and signature | Line |
|---|---|---|
| A room's timeline | `Room.timeline() async throws -> Timeline` (class `Room` at line 8446) | 10123 |
| Timeline with options | `Room.timelineWithConfiguration(configuration: TimelineConfiguration) async throws -> Timeline` | 10143 |
| Listen | `Timeline.addListener(listener: TimelineListener) async -> TaskHandle` (class `Timeline` at line 15622) | 15675 |
| Listener | `protocol TimelineListener { func onUpdate(diff: [TimelineDiff]) }` | 45865, 45867 |
| Diff type | `enum TimelineDiff { append(values: [TimelineItem]), clear, pushFront(value: TimelineItem), pushBack(value: TimelineItem), popFront, popBack, insert(index: UInt32, value: TimelineItem), set(index: UInt32, value: TimelineItem), remove(index: UInt32), truncate(length: UInt32), reset(values: [TimelineItem]) }` | 39109-39128 |
| Older messages | `Timeline.paginateBackwards(numEvents: UInt16) async throws -> Bool` | 15908 |
| Send | `Timeline.send(msg: RoomMessageEventContentWithoutRelation) async throws -> SendHandle` | 16014 |
| Text content | `messageEventContentFromMarkdown(md: String) -> RoomMessageEventContentWithoutRelation` (free function) | 50146 |
| Text content, given HTML | `messageEventContentFromHtml(body: String, htmlBody: String) -> RoomMessageEventContentWithoutRelation` (free function) | 50130 |

## What 26.04.01 answers for Open Verifications
- **SSO login-token flow:** the API exists: `startSsoLogin` returns an `SsoHandler`, whose `url()` is opened and whose
  `finish(callbackUrl:)` takes the callback URL. It has not been run against a Twake server.
- **Cross-process store lock:** the API exists: `ClientBuilder.crossProcessLockConfig` with
  `CrossProcessLockConfig.multiProcess(holderName:)`, plus `setSessionDelegate` for sharing refreshed tokens. It has
  not been run between the app and an extension.
- **Sliding sync:** the client-side setting exists (`slidingSyncVersionBuilder`, `HomeserverLoginDetails.slidingSyncVersion()`).
  This says nothing about which servers support it.

See [Open Verifications](../backlog/open-verifications.md).
