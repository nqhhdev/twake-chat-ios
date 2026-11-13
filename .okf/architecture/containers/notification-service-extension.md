---
type: Container
title: "Notification Service Extension"
description: "C4 level 2 - the separate process that fetches and decrypts a pushed event and rewrites the notification."
tags: [c4, container, push, e2ee]
status: draft
---
# Notification Service Extension

> Built: the `TwakeChatNSE` target (`TwakeChatNSE/NotificationService.swift`), bundle id `app.twake.ios.chat.nse` as
> the Flutter app's extension (ADR 0012), embedded in the app. Its content comes from MatrixData's
> `NotificationContentProxy`. Not yet seen running on a device: `simctl push` does not start notification service
> extensions, and a real APNs push needs a team-signed build.

| | |
|---|---|
| Kind | iOS Notification Service Extension (NSE), its own process with tight memory and time limits |
| Started by | A push from APNs carrying a room id and event id, no message content |
| Imports | `MatrixData`, `Domain`, `AppShared`. Never a feature module or `DesignSystem` screens |
| Reads | The same session store as the [App](app.md), in the App Group container, and the same Keychain group |

## What it does
1. Reads the room id and event id from the push payload.
2. Restores the user's session from the shared Keychain and opens the SDK store in the App Group container.
3. Asks the SDK's notification client for that event, which fetches and decrypts it.
4. Rewrites the notification title and body. If it cannot decrypt in time, it shows a generic text.

## Why it shares the store
In the Flutter app the main app runs the Dart SDK and the NSE runs the Rust SDK, so the NSE has no keys of its own and
the recovery key is copied into the Keychain for it (that app's ADR 35). Here both processes run the same SDK on the same
store, so no key copying is needed. See [ADR 0007](../../adr/0007-shared-session-store-app-group.md) and
[ADR 0009](../../adr/0009-push-gateway-and-nse-decryption.md).
