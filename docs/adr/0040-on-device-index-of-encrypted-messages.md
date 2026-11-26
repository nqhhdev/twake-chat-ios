---
type: ADR
title: "ADR 0040: Search encrypted chats through an on-device index of the messages the app decrypts"
description: "Proposed: the text of every message the app decrypts in an encrypted room is kept in an SQLite FTS5 index in the account's store directory; chat-list search merges it with the server's results and in-chat search adds its older hits; it never leaves the device and goes with the store at logout."
tags: [adr, search, e2ee, privacy]
status: draft
---
# ADR 0040: Search encrypted chats through an on-device index of the messages the app decrypts

**Status:** Proposed, 2026-11-26, from the project owner's direction of 2026-11-25; for the owner's review. Covers the
rest of issue #94 (edit history in encrypted rooms merged in #162).

## Context
The owner's direction of 2026-11-25, verbatim:

> "Max sure migrate 100% func in twake-on-matrix + twake-space-chat"
>
> "Pls auto and auto no need human review, I will review it after 100% func works well"

- The homeserver's `/search` cannot read encrypted rooms. The chat-list search (`ChatListViewModel.searchMessages`,
  `RoomSearchProxy.searchEverywhere`) therefore found nothing in them, and the in-chat search of an encrypted room
  (`RoomSearchViewModel`, on-device mode) only filtered the messages loaded in that session, paging back each time.
- The web client indexes decrypted messages locally (`twake-space-chat/src/ui/RoomSearch.tsx`,
  `roomSearchMatches.ts`). The pinned SDK ([ADR 0015](0015-pin-matrix-rust-components-swift-26-04-01.md)) exposes no
  message search.
- iOS ships SQLite with FTS5. The account's store directory is per account slot
  ([ADR 0039](0039-multiple-accounts.md)) and is deleted at logout (`MatrixAuthenticationRepository`).

## Decision
1. **What is indexed.** For a room the SDK reports as encrypted, every sent message a timeline of the app decrypts
   (the chat, a thread, a media tab, and the in-chat search, which pages back to the start) is recorded: event id,
   room, sender id and name, time, and the message text (text, emote, notice, location, caption, file name, poll
   question). An edit replaces the text; a redaction removes the row. Unencrypted rooms are not indexed: the server
   searches them.
2. **Where.** `message-index.sqlite3` in the account's store directory, an FTS5 table with the `unicode61` tokenizer
   (`remove_diacritics 2`), searched by word prefixes (every word must match). The index is opened per signed-in
   user and reopened when that user or the file changes, so another account or a deleted store never sees old rows.
   It is deleted with the store at logout. It is not cleared by Clear Cache, which empties the SDK caches only.
3. **Search.** The chat-list search merges the index's hits (up to 50, newest first) with the server's first page,
   without duplicates; if the server fails, the index's hits still show. The in-chat search of an encrypted room adds
   the index's hits for that room to the loaded messages, filtered by the same words, newest first.
4. **Privacy.** The index never leaves the device and is never logged ([ADR 0009](0009-push-gateway-and-nse-decryption.md)).
   It relies on iOS data protection like the SDK store; it is not encrypted separately.

## Consequences
**Good.** Encrypted messages are found from the chat list and found again in a chat without paging back. No new
dependency, no server change, nothing to clean beyond what logout already deletes.

**Costly.** Only messages the app has decrypted in a timeline are found: a room never opened since install, or
history never scrolled to, is missing until opened or searched in. Notifications decrypted by the extension are not
indexed. The index holds plaintext of encrypted messages on disk, protected by the device like the SDK's own caches.

**Alternatives rejected.** Opening every encrypted room in the background to backfill: heavy on battery and data,
and the SDK sync would fight it. A separate key for the index: the SDK store beside it is no better protected, so it
would add a key to manage for no gain. Waiting for SDK search: not in the pinned version.

## When to revisit
When the SDK exposes message search or an event-cache query; if the owner wants a background backfill or the
extension to index notifications; or if the index needs its own encryption.
