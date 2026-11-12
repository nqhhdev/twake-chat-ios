---
type: ADR
title: "ADR 0013: Port behaviour from one pinned Flutter commit"
description: "Behaviour is ported only from twake-on-matrix origin/main at 5a3e9e849; every Flutter feature is marked kept, deferred or dropped."
tags: [adr, scope, migration]
status: draft
---
# ADR 0013: Port behaviour from one pinned Flutter commit

**Status:** Proposed (2026-11-11), waiting for the project owner.

## Context
The native app reproduces behaviour from the Flutter app `twake-on-matrix`. On 2026-11-11 that repository had
several possible sources:

| Candidate | Commit | State |
|---|---|---|
| `origin/main` | `5a3e9e84920078d3d0fb5148146a179c1a06c04a` (2026-11-10, `version: 2.26.1+2330`) | Published |
| Local `main` | `382793527066e06813f3186c3bed5e29f9eb417f` (2026-11-08) | 11 commits behind `origin/main` |
| `feat/tom-3-drive-sso-foundation` | `b2aacdb69622339762c7dc834c80f79d06abd8ff` | One squashed Drive commit on top of `origin/main`; not merged |
| Working tree | `feat/tom-8-copy-message-link` at `5a3e9e849`, with uncommitted copy-message-link changes | Local only |

[ADR 0011](0011-v1-scope-core-chat.md) already fixes what v1 contains. It does not say which Flutter revision
is the reference, and it has no word for a feature that will never be rebuilt.

## Decision
**Baseline.** Behaviour is ported from `twake-on-matrix` at
`5a3e9e84920078d3d0fb5148146a179c1a06c04a`, which is on `origin/main`. Other branches (including
`feat/tom-3-drive-sso-foundation`), local `main`, uncommitted changes and later commits are not a source. Moving
the baseline needs a new ADR.

**Twake Drive** is out of v1 (deferred). Its SSO refresh-token vault is not needed either: v1 signs in with the
SDK login token only ([ADR 0008](0008-authentication-sso-and-discovery.md)).

**Status of each Flutter feature.** One line per row of the migration inventory's Features table.
*Kept* means in v1 per [ADR 0011](0011-v1-scope-core-chat.md). *Deferred* means listed in
[Deferred Features](../backlog/deferred-features.md). *Dropped* means it will not be rebuilt; nothing is dropped
until the owner says so.

| Flutter feature | Status | Reason |
|---|---|---|
| Login, homeserver discovery, SSO | Kept: discovery, SSO, sign-out. No password login; sign-up is a link | ADR 0011 Sign-in; [ADR 0008](0008-authentication-sso-and-discovery.md) |
| Multi-account and account switch | Deferred | Deferred Features: Multiple accounts |
| Chat list and archive | Chat list kept; archive deferred | ADR 0011 Chat list; Deferred Features: archive |
| Chat room (timeline, composer, send queue, albums, drafts, pinned messages) | Kept for the ADR 0011 timeline (text, images, video, files, replies, reactions, edits and deletions shown, read state, send and retry). Drafts, pinned messages, album sending, message splitting deferred | ADR 0011 Timeline; Deferred Features: Drafts, pinned messages, album sending |
| Chat details and profiles | Deferred | Deferred Features: Chat details, profile, roles |
| Search | Deferred | Deferred Features: Search |
| Contacts and phonebook | Deferred (needs the ToM server, not used in v1) | Deferred Features: Contacts |
| Invitation (ToM invite API, `invitation_selection`, `invitation_link_web`) | Deferred. Accepting a room invitation from the chat list is a different feature and is kept | Deferred Features: New group, invitations; Web invitation link; ADR 0011 Chat list |
| New group and new private chat | Deferred | Deferred Features: Contacts and new private chat; New group |
| Forward | Deferred | Deferred Features: Forward and share extension |
| Reactions | Kept | ADR 0011 Timeline |
| Public rooms and room access | Deferred | Deferred Features: Public rooms |
| Spaces and folders | Deferred | Deferred Features: Spaces, folders |
| E2EE: bootstrap, verification, recovery, keychain | Kept: encrypted rooms, recovery with the recovery key, verifying this session from another. ToM recovery words deferred | ADR 0011 Encryption; Deferred Features: ToM recovery words |
| Device settings | Deferred; signing this device out is kept | ADR 0011 Sign-in; Deferred Features: Device settings |
| Settings (language, chat, app lock, profile, contacts visibility) | Deferred; only the first language ships | Deferred Features: Settings and app lock; Localisation |
| Media viewer, download, URL preview | Showing images, video and files in the timeline is kept; full-screen viewer, download and URL preview deferred | ADR 0011 Timeline; Deferred Features: Media viewer, download, URL preview |
| Push notifications (incl. iOS NSE) | Kept | ADR 0011 Push; [ADR 0009](0009-push-gateway-and-nse-decryption.md) |
| Share into the app | Deferred | Deferred Features: Forward and share extension; [ADR 0012](0012-reuse-flutter-bundle-identifier.md) |
| VoIP and video call | Deferred | Deferred Features: Calls |
| App grid (Linagora apps) | Deferred | Deferred Features: app grid |
| Twake Drive picker | Deferred | Deferred Features: Drive picker |
| Stories | Deferred | Deferred Features: Stories |

**Proposed for dropping**, for the owner to decide. Each stays Deferred until then.

| Feature | Evidence |
|---|---|
| Stories (`add_story`, `story`) | No tests; the inventory says it is unclear whether it is still used |
| VoIP and video call (`dialer`) | `livekit_client` and `flutter_webrtc` are declared but not imported in `lib/`; needs VoIP push |
| App grid (`app_grid`) | No widget tests; depends on Linagora app configuration |
| Web invitation link (`invitation_link_web`, route `/chat/:matrixid`) | A web-only page in the Flutter app |
| Public rooms and room access (`public_rooms`) | Named as a candidate by the owner's card; no usage data found |

## Consequences
**Good.** One commit to compare against: a port can be checked line by line, and new Flutter work does not move the
target. Every Flutter feature has a status. **Costly.** Fixes merged to Flutter after `5a3e9e849` are not ported
unless a new ADR moves the baseline. The baseline includes album grouping (#3594); whether the v1 timeline shows
album events sent by other clients is not decided here. **Alternatives rejected.** The Drive branch: Drive is
deferred and the branch is not merged. Local `main`: 11 commits behind. A branch name instead of a commit: moves.

## When to revisit
When a Flutter fix after the baseline must be ported, when the owner decides a proposed drop, or when v1 is in
testers' hands and deferred features are ordered.
