---
type: ADR
title: "ADR 0023: Take features from the Twake Chat web client; design the experience after the best messengers"
description: "Proposed: what the iOS app does comes from linagora/twake-space-chat; how it looks and feels is decided here after iMessage, Telegram and WhatsApp, with Apple's components. Supersedes ADR 0013."
tags: [adr, scope, migration, ui]
status: draft
---
# ADR 0023: Take features from the Twake Chat web client; design the experience after the best messengers

**Status:** Proposed, 2026-11-14, from the project owner's direction of that day; for the owner's review. Supersedes
[ADR 0013](0013-flutter-baseline-and-feature-status.md) once accepted.

## Context
ADR 0013 proposed to port behaviour from one pinned commit of the Flutter app `twake-on-matrix`. On 2026-11-13 the
owner asked to keep only the Flutter app's logic and to design every screen as a native iOS experience. On 2026-11-14
the owner pointed at the Twake Chat web client, `github.com/linagora/twake-space-chat` (React, written from scratch,
its product decisions in `DECISION.md`, its feature phases in `docs/implementation-plan.md`), and said: take the
features from it, and decide the rest after good products such as iMessage, Telegram and WhatsApp.

The web client and the iOS app share accounts, rooms and Matrix data, so a feature also fixes what each client writes
into Matrix (room tags, account data such as `app.twake.chat.archived_rooms`, polls, threads, mentions).

## Decision
- **What the app does** comes from the web client: its feature list and, where it decides how Matrix data is written
  or read, its data formats, so a user moving between the web and the iPhone sees the same chats, archive, favourites,
  polls and mentions. The Flutter app remains the reference for logic the web client does not have (push through the
  Twake gateway, the iOS share extension, the bundle identifier, ADR 0009, ADR 0012).
- **How it looks and feels** is decided in this repository, after iMessage, Telegram and WhatsApp, with Apple's
  Human Interface Guidelines and system components (ADR 0002, ADR 0022). Neither the web nor the Flutter look is
  copied.
- **Not now:** threads (later), calls (only if the owner asks), stories, emotes and folders.
- The feature plan that lists the web client's features with their iOS state is kept by the owner; it is not part of
  this repository until the owner decides so.

## Consequences
- ADR 0013 is superseded. ADR 0011 (version 1 is core chat only) is to be reviewed against the web feature list.
- Each feature names its web source (`docs/implementation-plan.md` phase or `DECISION.md` entry) in `.okf/log.md`.
- Where the web client and the Flutter app write the same thing differently (for example the archive: account data
  on the web, rooms left in Flutter), the web client's form wins, and the change is logged.
