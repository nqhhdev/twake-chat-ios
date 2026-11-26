---
type: ADR
title: "ADR 0041: Send the pictures of an album as raw events with the batch key"
description: "Proposed: a send of two or more pictures or videos uploads each file and sends its m.image or m.video with sendRaw, carrying app.twake.chat.batch, encrypting the file in the app in an encrypted room; it has no local echo."
tags: [adr, media, albums, encryption]
status: draft
---
# ADR 0041: Send the pictures of an album as raw events with the batch key

**Status:** Proposed, 2026-11-26, for #210.

## Context
- Flutter and the web tie the files of one send with a UUID under `app.twake.chat.batch` on each file
  (`twake-on-matrix` `lib/domain/media_album/policy/media_batch_stamp.dart`); the reply goes on the first file only.
- iOS reads the key (`MediaBatch`) but `Timeline.sendImage` of the pinned SDK
  ([ADR 0015](0015-pin-matrix-rust-components-swift-26-04-01.md)) takes no extra content keys, so an iOS album
  shows as single pictures elsewhere. `sendGallery` (MSC4274) is read by neither client.
- `Room.sendRaw` encrypts the event in an encrypted room but not the file; `Client.uploadMedia` uploads bytes as they
  are.

## Decision
- A send of two or more pictures or videos gets one lowercase UUID; each of them is uploaded with
  `Client.uploadMedia` and sent with `Room.sendRaw` as `m.image` or `m.video`, with `body` (caption or file name),
  `filename`, `info` (size, mime type, width, height, blurhash, duration, thumbnail) and `app.twake.chat.batch`. The
  reply goes on the first file; in a thread each file carries the thread relation.
- In a room that is not known to be unencrypted, the file and its thumbnail are encrypted in the app as Matrix
  attachments v2 (AES-256-CTR, random 256-bit key and 64-bit IV with a zero counter, SHA-256 of the ciphertext,
  JWK key) and sent under `file` and `thumbnail_file`.
- A single picture, voice message or file keeps the SDK's send, with its local echo and progress.

## Consequences
**Good.** Albums from iOS group on Flutter and the web. **Costly.** An album has no local echo or per-file progress:
the composer shows "Sending…" until each event is sent, and a failed file is reported, not left to retry. The app
carries its own attachment encryption, tested against `openssl`. **Alternatives rejected.** `sendGallery`: no other
client reads it. Editing each picture after sending to add the key: an edit does not change how clients group the
original.

## When to revisit
The SDK accepts extra content keys on an upload, or Flutter and the web read MSC4274 galleries.
