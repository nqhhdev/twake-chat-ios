---
type: ADR
title: "ADR 0011: Version 1 is core chat only"
description: "v1 ships sign-in, chat list, timeline, encryption recovery and push; every other Flutter feature is deferred."
tags: [adr, scope, roadmap]
status: draft
---
# ADR 0011: Version 1 is core chat only

**Status:** Accepted (chosen by the project owner, 2026-11-11).

## Context
The Flutter app has many features: contacts, spaces, calls, drive picker, share extension, multiple accounts, stories,
search, forwarding and more. Rebuilding all of them before a first release would delay learning whether the native
architecture holds.

## Decision
Version 1 contains:

| Area | In v1 |
|---|---|
| Sign-in | Server discovery, SSO sign-in, sign-out |
| Chat list | Rooms ordered by activity, unread state, invitations |
| Timeline | Text, images, video and files; replies; reactions; edits and deletions shown; read state; send and retry |
| Encryption | Encrypted rooms, recovery with the recovery key, verifying this session from another one |
| Push | Notifications with decrypted text |

Everything else is deferred and tracked in [Deferred Features](../backlog/deferred-features.md). A deferred feature
needs no code, flag or placeholder in v1.

## Consequences
**Good.** A small release that exercises every hard part: sync, encryption, push, two iOS versions. **Costly.** The
native app cannot replace the Flutter app for users who rely on deferred features. **Alternatives rejected.** Full
parity first: too long before any feedback. Text-only slice: skips encryption and push, the riskiest parts.

## When to revisit
When v1 is in testers' hands; the order of deferred features is decided then.
