---
type: ADR
title: "ADR 0017: What the native app keeps from the Flutter app and what it deletes"
description: "Proposed: lists the identifiers and server contracts the update keeps unchanged and the Flutter stores the first-launch cleanup deletes."
tags: [adr, release, push, security, migration]
status: draft
---
# ADR 0017: What the native app keeps from the Flutter app and what it deletes

**Status:** Proposed. The project owner answered "Approved" on card TWAK-3 (2026-11-11), but open points 1 to 4 at
the end are **not** settled by that answer. Open point 1 shows that the cleanup in
[ADR 0012](0012-reuse-flutter-bundle-identifier.md) cannot remove the Flutter app's own device and pusher as written,
and open point 2 decides how updating users recover encryption. Deleting the Flutter app's recovery-key items is not
open: Accepted ADR 0012 already decides it, in line with [ADR 0007](0007-shared-session-store-app-group.md). This ADR
becomes Accepted only when the owner rules on the open points; if open point 1 is answered with option (a), a new ADR
supersedes ADR 0012's cleanup clause first. Until then no cleanup code is written.

## Context
[ADR 0012](0012-reuse-flutter-bundle-identifier.md) decided that the native app installs over the Flutter app as an
update. The user signs in again, nothing from the Flutter session is reused, and a first-launch cleanup deletes what the
Flutter app left behind. ADR 0012 did not list each identifier and store one by one, and did not say whether the ToM
backend and push gateway contracts must stay the same. This ADR lists them. Every row names the place in the Flutter
repository (`twake-on-matrix`) where it was read on 2026-11-11.

## Decision

### Identifiers kept unchanged

| Identifier | Value | Where the Flutter app sets it |
|---|---|---|
| App, extension, share extension | `app.twake.ios.chat`, `app.twake.ios.chat.nse`, `app.twake.ios.chat.TwakeShareExtension` | `ios/NSE/Info.plist:10`, Xcode project and entitlements |
| App Group | `group.app.twake.ios.chat` | `ios/Runner/Runner.entitlements:16`, `ios/NSE/NSE.entitlements:7` |
| Keychain access group | `KUT463DS29.app.twake.ios.chat` (team prefix written out) | `lib/config/app_config.dart:178`, `ios/NSE/Info.plist:8` |
| URL schemes | `twake.chat`, `matrix`; SSO callback `twake.chat://login` | `ios/Runner/Info.plist:43-44`, [ADR 0008](0008-authentication-sso-and-discovery.md) |
| Associated domains | `applinks:links.twake.app`, `webcredentials:links.twake.app` | `ios/Runner/Runner.entitlements:9-10` |
| Communication-notification entitlement | `com.apple.developer.usernotifications.communication` | `ios/Runner/Runner.entitlements:12` |
| Push app ids | `app.twake.ios.chat` in release builds, `app.twake.ios.chat.sandbox` otherwise | `lib/config/app_config.dart:132-138` |

### Push gateway contract: kept unchanged
The native app registers its pusher with the same fields as the Flutter app (`lib/utils/background_push.dart:295-321`):
`kind: http`; `data.format: event_id_only` (`app_config.dart:164`); `data.url` =
`https://push.twake.app/_matrix/push/v1/notify`, overridable by the build setting `PUSH_NOTIFICATIONS_GATEWAY_URL`
(`app_config.dart:140-145`); `data.default_payload.aps` = `mutable-content: 1`, `content-available: 1`, `badge: 1`,
`sound: default`, `alert.loc-key: newMessageInTwake`, `alert.loc-args: []`; and
`data.default_payload.pusher_notification_client_identifier` = SHA-256 of the Matrix user id
(`lib/presentation/extensions/client_extension.dart:41`).

The extension reads these payload keys: `room_id`, `event_id`, `unread_count`, `receiver_id`,
`pusher_notification_client_identifier` (`ios/NSE/NotificationConstants.swift:21-25`).

This answers the open point in [ADR 0009](0009-push-gateway-and-nse-decryption.md): the format is `event_id_only`.

### ToM backend contract: kept unchanged, not used in v1
The ToM server is shared with the Android and web apps, so this app cannot change it. The paths the Flutter app sends
on the wire are below. Two families exist: `recoveryWords` and `addressbook` use the bare `ServicePath.path`, with no
version segment; the others go through `generateTomEndpoint()` or `generateTomUserInfoEndpoint()`, which insert
`/_twake/v1` (`lib/data/network/tom_endpoint.dart:4-48`).

| Wire path | Method | Call site |
|---|---|---|
| `/_twake/recoveryWords` | GET, POST, DELETE | `lib/data/network/recovery_words/recovery_words_api.dart:14,21-22,34` |
| `/_twake/addressbook` | GET, POST | `lib/data/network/contact/address_book_api.dart:15,25-26` |
| `/_twake/v1/invite` | POST | `lib/data/network/invitation/invitation_api.dart:21-22` |
| `/_twake/v1/invite/generate` | POST | `lib/data/network/invitation/invitation_api.dart:46-47` |
| `/_twake/v1/invite/<invitationId>/status` | GET | `lib/data/network/invitation/invitation_api.dart:71,78` |
| `/_twake/v1/user_info/<userId>` | GET | `lib/data/network/user_info/user_info_api.dart:15-19` |
| `/_twake/v1/user_info/<userId>/visibility` | GET, POST | `lib/data/network/user_info/user_info_api.dart:24-38` |
| `/_twake/v1/video_call/rooms` | POST | `lib/data/network/video_call/video_call_api.dart:14-15` |

These paths stay byte-for-byte unchanged. Version 1 calls none of them ([ADR 0011](0011-v1-scope-core-chat.md)),
unless the owner decides otherwise on open point 2 below.

### Flutter stores the first-launch cleanup deletes
The native app never reads these stores, except where open point 1 below decides otherwise. It deletes them once. The
recovery-key items in the two secure-storage rows are deleted whatever the open points decide (ADR 0012).

| Store | Location and keys | Where the Flutter app writes it |
|---|---|---|
| Matrix Dart SDK database (app session, access token, pusher, all E2EE keys) | App container `Documents/databases/<client name>.db`; client name `Twake Chat ios ` (release) or `Twake Chat ios Debug` | `lib/utils/open_sqflite_db.dart:13-17`, `lib/utils/platform_infos.dart:108-110` |
| Hive stores | App container `Documents/hive/` (debug builds: `Documents/hive_debug/`), collections `tom_db` and `<client name>`; plus any box `Hive.initFlutter()` opens at the `Documents/` root. Application Support is used on Linux only | `lib/main.dart:59-63`, `lib/data/hive/hive_collection_tom_database.dart:110-129`, `lib/utils/matrix_sdk_extensions/flutter_hive_collections_database.dart:92-114` |
| Hive cipher key | Default secure storage item `hive_encryption_key` | `lib/utils/matrix_sdk_extensions/flutter_hive_collections_database.dart:26` |
| UserDefaults (SharedPreferences) | Every key in `SettingKeys`, the legacy `chat.fluffy.*` keys, `im.twake.store.clients`, `im.fluffychat.store.clients`, `im.twake.store.sync_filter_include_leave_v1*` | `lib/config/setting_keys.dart:1-32` and after, `lib/utils/client_manager.dart:18-29` |
| Default secure storage | `chat.twake.app_lock`, `ssss_recovery_key_<userId>` | `lib/config/setting_keys.dart:18`, `lib/data/repository/recovery_key_storage_repository_impl.dart:13` |
| Shared Keychain, account `app.twake.ios.chat.sessions` in group `KUT463DS29.app.twake.ios.chat` | One JSON item per user id (`session`, `pusherNotificationClientIdentifier`, `dedicated`); `ssss_recovery_<userId>`; `nse_ed25519_<deviceId>`; `own_keys_checked_<deviceId>` | `lib/domain/keychain_sharing/keychain_sharing_manager.dart:13-52, 94-104, 222` |
| Old extension's Rust SDK store and caches | App Group container `Library/Application Support/app.twake.ios.chat/Sessions` and `Library/Caches` | `ios/NSE/URL.swift:43-67` |
| Old extension's settings | UserDefaults suite `group.app.twake.ios.chat` | `ios/NSE/Sources/Other/NSESettings.swift:20` |

The new SDK store ([ADR 0007](0007-shared-session-store-app-group.md)) uses a directory other than
`Library/Application Support/app.twake.ios.chat/Sessions`, so the cleanup can delete the old one without touching the
new one. The proposed name is in open point 4.

These rows are the expected inputs of the first-launch cleanup test named in
[Constraints](../engineering/constraints.md).

### Open points the owner must still rule on
1. **The cleanup signs out the wrong device.** The only session the Flutter app writes to the shared Keychain is the
   dedicated notification device, saved with `dedicated: true` (`keychain_sharing_manager.dart:94-104`). The app's own
   device, access token and pusher are in the SQLite database, which ADR 0012 says the native app does not read. So the
   cleanup in ADR 0012 signs out the notification device only. The Flutter app's device and its pusher stay registered
   on the server. The APNs token belongs to the bundle id, so that pusher keeps sending pushes to the new app, carrying
   the old identifier, and the new extension cannot decrypt them. Options:
   (a) read the access token from the SQLite database once, only to call logout. This contradicts ADR 0012 and needs a
   superseding ADR;
   (b) leave the old device and make the extension drop pushes whose `pusher_notification_client_identifier` or
   `receiver_id` does not match its own session. The old device stays in the user's device list until they remove it.
   This is a product and security decision for the owner.
2. **Upgrading users lose automatic encryption recovery.** The Flutter app gets the recovery key from ToM recovery words
   during bootstrap (`lib/pages/bootstrap/tom_bootstrap_controller.dart:118-149`), so most users have never seen their
   key. ADR 0007 forbids storing the key; ADR 0011 says recovery uses the recovery key. Deleting the copies the Flutter
   app kept (`ssss_recovery_<userId>`, `ssss_recovery_key_<userId>`) is already decided by Accepted
   [ADR 0012](0012-reuse-flutter-bundle-identifier.md), in line with ADR 0007, and is not part of this open point. What
   stays open is the recovery path: either v1 calls `GET /_twake/recoveryWords` once, at recovery time and without
   storing the result, or the owner accepts that updating users must type a key many of them do not have, and lose
   encrypted history if they cannot.
3. **Signing team.** The Keychain group carries team prefix `KUT463DS29`. The native app keeps the shared Keychain and
   the App Group only if it is signed by that team.
4. **Name of the new SDK store directory.** Proposed: `Library/Application Support/TwakeChat/SDK` inside the App Group
   container, which shares no path prefix with the old `Library/Application Support/app.twake.ios.chat/` tree, so
   deleting the old tree cannot reach it. The owner confirms or picks another name.

Each open point is tracked in [Open Verifications](../backlog/open-verifications.md) until the owner rules.

## Consequences
**Good.** One list to implement and test the cleanup from; push keeps working with no server change; the ToM server is
untouched. **Costly.** The push payload keys and pusher fields are frozen: changing them later needs a gateway and
Android/web check. Until open point 1 is decided, the cleanup in ADR 0012 cannot be implemented as written.
**Alternatives rejected.** Changing the pusher format or payload for the native app: the gateway is shared and
`event_id_only` already fits the extension design of ADR 0009.

## When to revisit
When the owner rules on the open points; when the push gateway or ToM server changes its contract; or if the app moves
to another signing team.
