---
type: ADR
title: "ADR 0035: The formats of spoilers, picture descriptions, emotes and scheduled messages"
description: "Proposed: spoilers and emotes are sent as Matrix HTML with a plain body that hides the spoiler; a picture's description is its caption; emotes come from MSC2545 packs; scheduled messages use MSC4140 only where the server announces it and never in an encrypted room; the author's removal of a link preview waits for a web format."
tags: [adr, composer, timeline, formats, msc2545, msc4140]
status: draft
---
# ADR 0035: The formats of spoilers, picture descriptions, emotes and scheduled messages

**Status:** Proposed, 2026-11-26. It follows the project owner's direction of 2026-11-25 ("Max sure migrate 100% func
in twake-on-matrix + twake-space-chat: If funcs depends on other server ( difference bettwen Matrix SDK) pls write
ADR to enable or disable it.") and [ADR 0026](0026-matrix-first-client-server-features.md).

## Context
- The pinned SDK ([ADR 0015](0015-pin-matrix-rust-components-swift-26-04-01.md)) turns Markdown into an opaque
  message content whose plain body is the Markdown source. It has no spoiler syntax, no emote images and no delayed
  events.
- **Spoilers (#178).** Matrix marks one with `<span data-mx-spoiler>`; the web hides it until clicked (MSG-23).
- **Picture descriptions (#179).** Matrix has no alternative-text field. The web uses a picture's caption as its alt
  text, and the file name otherwise (`MessageItem.tsx`, `alt={message.text || attachment.name}`).
- **Emotes (#186).** Flutter reads MSC2545 packs (`im.ponies.user_emotes`, `im.ponies.room_emotes`,
  `im.ponies.emote_rooms`) and sends `<img data-mx-emoticon src="mxc://…" alt=":code:">`.
- **Removing a link preview (#185).** On `twake-space-chat` `main` (2026-11-26) it is a plan item only (CMP-09),
  with no event format.
- **Scheduled messages (#184).** The web now schedules text messages as MSC4140 delayed events
  (`MatrixScheduledMessages.ts`, issue #1185): only when `/versions` lists `org.matrix.msc4140`, never in an
  encrypted room, since a delayed event is not encrypted.

## Decision
1. **Spoiler.** The composer writes `||text||`. A message holding a spoiler or a known emote is sent through
   `messageEventContentFromHtml`: its HTML is built from the inline Markdown (bold, italic, strikethrough, code,
   links, line breaks), the spoiler wrapped in `<span data-mx-spoiler>`; its plain body is the Markdown with each
   spoiler replaced by `[Spoiler]`, so notifications and plain clients do not reveal it. Other messages keep the SDK's
   Markdown.
2. **Picture description.** The send preview's ALT button describes one picture; the description is sent as that
   picture's caption (the batch caption still goes with the last picture and wins there). The timeline gives a
   picture its caption as the VoiceOver label.
3. **Emotes.** Images whose `usage` (or their pack's) includes `emoticon`, or is absent, with a shortcode of
   letters, digits and `_+-.`, are emotes. A known `:code:` outside code is sent as
   `<img data-mx-emoticon src alt title height="32">` and stays `:code:` in the plain body. A reaction whose key is
   an `mxc://` URL shows as its picture.
4. **Scheduled messages.** Text only, through `PUT …/send/m.room.message/{txn}?org.matrix.msc4140.delay=<ms>`, listed
   with `GET /_matrix/client/unstable/org.matrix.msc4140/delayed_events`, cancelled or sent now through the same
   unstable API. The entry is hidden when `/versions` does not list `org.matrix.msc4140` and in an encrypted room.
5. **Link preview removal.** Not built until the web defines its event format; this ADR is then superseded.

## Consequences
**Good.** Every format is read by the web and Flutter; nothing needs a Twake service. **Costly.** A message with a
spoiler or an emote loses block Markdown (lists, code blocks, quotes) and its plain body hides the spoiler, so editing
it puts `[Spoiler]` back in the composer. A description shows to everyone as a caption. Scheduled messages do not
work in encrypted rooms. **Alternatives rejected.** A custom alt-text key: no other client reads it. Sending the
spoiler in clear in the plain body: notifications would show it. Encrypting a delayed event ourselves: the SDK does
not expose the room's encryption for raw content.

## When to revisit
The SDK gains spoiler or delayed-event support; the web defines link preview removal; Matrix adds an alt-text field.
