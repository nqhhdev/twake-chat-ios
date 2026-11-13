---
type: Container
title: "Share Extension"
description: "C4 level 2 - the system share sheet entry that hands what another app shares to the app."
tags: [c4, container, share]
status: draft
---
# Share Extension

> Built: the `TwakeChatShare` target (`TwakeChatShare/ShareViewController.swift`), bundle id
> `app.twake.ios.chat.TwakeShareExtension` as the Flutter app's extension (ADR 0012), embedded in the app.

| | |
|---|---|
| Kind | iOS Share Extension (`com.apple.share-services`), its own process |
| Started by | The user picking Twake Chat in another app's share sheet: pictures, videos, files (up to 15), text or a web link |
| Imports | `AppShared` only. Never the SDK, `MatrixData` or a feature module |
| Writes | The pending share (`SharedInbox`, `Library/Caches/Shared` in the App Group container) |

## What it does
1. Copies each shared picture, video or file into the inbox folder and keeps text and web links as text.
2. Writes `manifest.json` (`SharedItems`) and opens the [App](app.md) with `twake.chat://share`.
3. Closes; it shows no screen of its own.

The app then reads the inbox, asks which chat to send to ("Send to"), opens that chat, puts the text in the composer
and sends the files; Cancel deletes the share. This is the Flutter app's flow (`receive_sharing_intent`).

## Why it does not send
Sending would need the SDK, a restored session and a sync in the extension, beyond what a share extension can rely on
for memory and time. The app already holds them.

## Known limits
- An extension may not call `UIApplication.open`, and this Xcode requires `APPLICATION_EXTENSION_API_ONLY`; the
  extension asks the application object it finds in its responder chain to open the URL through the Objective-C
  runtime, as `receive_sharing_intent` does. A later iOS can stop this; then the share stays in the inbox until the
  user opens the app.
- One share waits at a time: a new one replaces it.
