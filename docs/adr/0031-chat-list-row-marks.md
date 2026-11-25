---
type: ADR
title: "ADR 0031: Mark chat list rows from what the SDK syncs, and read presence only when a row shows"
description: "Proposed: a direct chat's presence dot is read with one request when its row shows, at most once a minute per person, never on a timer, because the pinned SDK syncs no presence."
tags: [adr, chat-list, presence, sdk]
status: draft
---
# ADR 0031: Mark chat list rows from what the SDK syncs, and read presence only when a row shows

**Status:** Proposed, 2026-11-25, for the chat list parity items #136, #144 and #145 (epic #112).

## Context
- The web client puts a presence dot on the avatar of a direct chat (`src/ds/PresenceBadge`): green online, amber
  away, nothing offline. It reads presence with `GET /presence/{userId}/status`, because sliding sync carries none, and
  keeps a shown person live with a 15 s poll (`src/ui/useStatus.ts`).
- matrix-rust-components-swift 26.04.01 (ADR 0015) exposes no presence at all: no field on `RoomInfo`, `RoomMember`
  or `RoomHero`, and no presence listener. Simplified sliding sync has no presence extension.
- The chat screen already polls the other person every 15 s (`RoomViewModel.watchPresence`); issue #111 asks not to add
  more of that, and #136 says to drop the dot rather than poll per row.
- A homeserver may turn presence off (Synapse `presence.enabled: false`); the request then answers offline or fails.

## Decision
- The chat list row of a direct chat asks for the other person's presence once when the row shows. The answer is kept
  per person and not asked again for 60 seconds, however often the row scrolls in and out. There is no timer: a row
  that stays on screen keeps the dot it got.
- The other person is the room's only hero (`RoomInfo.heroes`) when the room is direct; a direct chat with more than
  one hero, or none, shows no dot.
- `online` with recent activity shows a green dot; `unavailable`, or `online` without activity for five minutes, shows
  an amber dot; anything else, a failed request and a server without presence show no dot. VoiceOver reads "Online" or
  "Away".
- Groups, spaces and invitations never ask.

## Consequences
**Good.** The dot matches the web's colours and rules, needs no SDK change, and costs one small request per direct chat
shown per minute at most; nothing runs while the list is idle or in the background. **Costly.** A dot can be up to a
minute old, and older while the row stays on screen; the list does not see a person go offline until the row shows
again. **Alternatives rejected.** Polling every shown row like the web: more requests and battery for a decoration
(#111). No dot until the SDK syncs presence: leaves a web feature out with no date for the SDK.

## When to revisit
When the pinned SDK exposes presence from sync, switch the dot to it and remove the request. When #111 changes how the
chat screen reads presence, use the same source for the row.

## Addendum: room kind badge (#144), 2026-11-25
- The avatar of a row carries the web's badge (`src/ui/roomBadgeKind.ts`), in this order: a space shows a cube; a
  Broadcast (only moderators post, `RoomSummary.isBroadcast`) a megaphone; a direct chat nothing; a group whose join
  rule is public (`RoomInfo.isPublic`) a globe; any other group two people. VoiceOver reads "Space", "Broadcast",
  "Public group" or "Group".
- The web's voice-room badge is left out: the app has no voice rooms.
- The pinned SDK gives no `m.room.create` type on `RoomInfo`, so a Broadcast is found by its power levels, as the rest
  of the app already does, not by the `app.twake.chat.page` type.
- The badge and the presence dot sit in the same corner; they never meet, since only a direct chat has a dot and a
  direct chat has no badge.
