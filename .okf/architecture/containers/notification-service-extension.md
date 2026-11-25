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
> `NotificationContentProxy`. Not yet seen running on a device (nor the communication notification, Reply and Mark as
> read): `simctl push` does not start notification service
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
5. Shows nothing for an event that does not notify: an edit, a reaction, a redaction, a deleted message, or one the
   user's push rules filter out (`NotificationContentProxy`).
6. Sets the app icon badge to the push's `unread_count`, the homeserver's count, when the push has one.
7. Shows nothing for the user's own message (a defensive check: the homeserver does not push one).
8. Groups notifications by room (`threadIdentifier` is the room id) and writes the Matrix thread root, if any, under
   `thread_id` in the notification's `userInfo`, so a tap opens that thread.
9. Makes it a communication notification (`CommunicationNotification`): an incoming `INSendMessageIntent` with the
   sender's name and avatar and, in a group, the group's name and avatar, donated, then `content.updating(from:)`.
   Avatars are 96 px thumbnails fetched with a 3 s limit each; without one the notification still shows. The app holds
   the `com.apple.developer.usernotifications.communication` entitlement and lists `INSendMessageIntent` in
   `NSUserActivityTypes`, as the Flutter app does.
10. Gives a message the category `message` (the Flutter value), which offers Reply and Mark as read; so does the
    generic text, since neither action needs the message. An invite gets no category.

## Reply and Mark as read
The actions are handled by the [App](app.md), never by the extension: iOS starts the app in the background for an
action without the `.foreground` option. `AppDelegate` turns the response into a `NotificationAction` and
`PushCenter.handle` starts the session restore (`RootCoordinator.start()`, a no-op when it already ran) and calls
MatrixData's `NotificationActionProxy` on the app's own client, under the app's lock name `app`: no second client and no
third lock holder are opened on the shared store (ADR 0007). The proxy waits up to 15 s for the client, then sends the
reply directly (`Room.sendRaw`, so it is on the server before the handler returns rather than queued), in the thread
when the notification was about one, and marks the room read as the chat list does (`markAsRead` then the unread flag
off). Mark as read does the second part alone. A reply that fails posts a local notification saying it was not sent;
tapping it opens the chat. A tap on a notification opens its room and, with `thread_id`, its thread.

## Why it shares the store
In the Flutter app the main app runs the Dart SDK and the NSE runs the Rust SDK, so the NSE has no keys of its own and
the recovery key is copied into the Keychain for it (that app's ADR 35). Here both processes run the same SDK on the same
store, so no key copying is needed. See [ADR 0007](../../../docs/adr/0007-shared-session-store-app-group.md) and
[ADR 0009](../../../docs/adr/0009-push-gateway-and-nse-decryption.md).
