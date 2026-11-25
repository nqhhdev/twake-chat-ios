---
type: ADR
title: "ADR 0028: GIFs through twake-common-proxy, stickers from image packs, checklists off until defined"
description: "Proposed: the GIF picker calls twake-common-proxy with an OpenID token and shows only when a proxy URL is built in and the proxy offers GIFs; stickers come from MSC2545 image packs; checklists stay off until the web defines an event format."
tags: [adr, composer, gifs, stickers, checklists, privacy, server-dependent]
status: draft
---
# ADR 0028: GIFs through twake-common-proxy, stickers from image packs, checklists off until defined

**Status:** Proposed, 2026-11-25. It follows the project owner's direction of that day: "Max sure migrate 100% func
in twake-on-matrix + twake-space-chat: If funcs depends on other server ( difference bettwen Matrix SDK) pls write
ADR to enable or disable it." and "My goal: This repo will be a new app chat no only Twake Chat".

## Context
- [ADR 0026](0026-matrix-first-client-server-features.md) turns a non-Matrix feature on only when it is detected, and
  leaves the GIF picker to this ADR. Image packs (MSC2545) are plain Matrix there.
- **GIFs.** The web client (`twake-space-chat`, decisions D63, D146, D276, D640) has a GIFs tab beside the emojis.
  It never calls the GIF provider (Klipy) itself: it calls twake-common-proxy
  (`github.com/linagora/twake-common-proxy`), one proxy shared by the Twake apps. The proxy URL is a deployment
  setting (`TWAKE_PROXY_URL`); without it there is no GIF entry. The client authenticates with a Matrix OpenID
  token (`POST /_matrix/client/v3/user/{userId}/openid/request_token`), never its access token, plus
  `X-Matrix-Server-Name`. `GET /v1/modules` says whether the proxy offers GIFs and gives the search placeholder
  Klipy requires; `GET /v1/gif/trending` and `GET /v1/gif/search` return pages of media URLs on the proxy, signed
  for one to two hours. The picked GIF (the `sm` GIF first) is downloaded through the proxy and sent as an
  `m.image` (`image/gif`), uploaded to the homeserver like any picture, so receivers never call a third party.
- **GIFs off.** The owner of a channel can turn GIFs off with the state event `app.twake.chat.gifs`
  (`{"enabled": false}`, state key `""`); a direct chat ignores it (D146).
- **Stickers.** The Flutter app has a sticker picker over MSC2545 image packs (`im.ponies.room_emotes` room state,
  `im.ponies.user_emotes` account data, `im.ponies.emote_rooms` for packs of other rooms) that sends an `m.sticker`
  event (`body`, `url`, `info`), but no button opens it (`sendStickerAction` has no caller). The web client shows
  a received `m.sticker` as unsupported and has no picker. The pinned SDK (ADR 0015) reads `m.sticker` events but
  no image pack.
- **Checklists.** The web implementation plan lists "checklists next to polls" (THR-11) and its research marks the
  format as an open question ("MSC à vérifier"). On `twake-space-chat` `origin/main` (`67f2ca6e`, 2026-11-23) no
  code reads or sends a checklist event, and no MSC defines one.

## Decision
1. **GIF provider.** The app uses twake-common-proxy exactly as the web does: the same endpoints, an OpenID token
   with `X-Matrix-Server-Name` (a new token after a 401, once), media only from the proxy's origin, the `sm` GIF
   first, sent as an `m.image` with its mime type, in the thread or as the reply in progress. No provider SDK and
   no provider key ship in the app.
2. **Configuration.** The proxy URL is the build setting `TWAKE_PROXY_URL`, read through the `Info.plist` key
   `TwakeProxyURL` in the composition root. An empty value builds no GIF repository, and the entry point is hidden.
   The proxy URL is not a secret.
3. **Default.** Debug builds point at the development proxy the web documents
   (`https://proxy.dev.twake.lin-saas.com`). Release stays empty until the owner names the production proxy. With a
   URL set, GIFs show only when `/v1/modules` lists `gif` for the signed-in account; a plain Matrix server the
   proxy does not serve gets an error from it, so it has no GIF entry. No well-known key is read: the web reads
   none either.
4. **Room switch.** The picker is hidden in a room whose `app.twake.chat.gifs` state says `enabled: false`, unless
   the room is a direct chat. Hiding received GIFs and the owner's switch in the room details are not part of
   this decision's first change; they follow in their own change.
5. **Privacy.** What the user types in the GIF search leaves the device: the proxy forwards it to Klipy. The
   device's IP address reaches only the proxy. The app never logs or tracks a search (ADR 0009 for logs).
6. **Stickers.** The app reads MSC2545 packs from the room (every `im.ponies.room_emotes` state key), the user's
   account data and the rooms `im.ponies.emote_rooms` names, keeps images whose `usage` (or their pack's) includes
   `sticker` or is absent, and sends the picked one as `m.sticker` with `body`, `url` and `info`, as the Flutter
   code does. The entry point shows only when at least one pack has a sticker; a plain Matrix server needs nothing
   more, since packs are ordinary state and account data. A received `m.sticker` shows as a picture without a
   bubble, as before.
7. **Checklists.** Off. No checklist code ships until `twake-space-chat` or an MSC defines the event format; this
   ADR is then superseded by one that names that format.

## Consequences
**Good.** GIFs work as on the web with the same privacy, no provider key in the binary, and a server without the
proxy simply hides the entry. Stickers work on any Matrix server that has packs. **Costly.** GIFs depend on a Twake
service; Release has none until the owner sets its URL. Reading every room state event for packs costs one request
per opening of the picker. Packs cannot be created or edited in this app yet. **Alternatives rejected.** Calling a
GIF provider (Klipy, Tenor, Giphy) directly from the device: it ships a key and sends the user's IP to the provider.
A well-known key for the proxy URL: no Twake server publishes one. Guessing a checklist format: it would not be
readable by the web once it defines its own.

## When to revisit
The owner names the production proxy URL or asks for GIFs on non-Twake servers; the web defines checklists; the SDK
gains image pack support.
