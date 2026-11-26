---
type: ADR
title: "ADR 0038: Make calls in the app with the Element Call widget, offered only on a server with a LiveKit token service"
description: "Proposed: in-app calls run Element Call in a web view driven by the SDK's widget driver, as Element X does; they appear only when the well-known names a LiveKit token service (livekit_service_url), otherwise the Meet link of #92 stays. CallKit reports the call; ringing an incoming call in the background is left for later."
tags: [adr, calls, matrixrtc, livekit, element-call, callkit]
status: draft
---
# ADR 0038: Make calls in the app with the Element Call widget, offered only on a server with a LiveKit token service

**Status:** Proposed, 2026-11-25 (#191, parity epic #112). Decided without the owner, on the owner's standing direction
of 2026-11-25 to carry on without asking; the owner reviews it afterwards.

## Context
The web client calls in the app (`twake-space-chat` `DECISION.md` D25, D30, D106): MatrixRTC membership
(`org.matrix.msc3401.call.member`, MSC3401), LiveKit media, a token service named in the homeserver's
`.well-known/matrix/client` (`org.matrix.msc4143.rtc_foci`, `livekit_service_url`, MSC4195 `/sfu/get`), media
encrypted per participant in an encrypted room, and a ring (`org.matrix.msc4075.rtc.notification`, MSC4075). This is
the protocol Element Call speaks. iOS had the Meet link and call events only ([ADR 0026](0026-matrix-first-client-server-features.md), #92).

The pinned SDK 26.04.01 ([ADR 0015](0015-pin-matrix-rust-components-swift-26-04-01.md)) exposes what Element X iOS
uses to embed Element Call: `newVirtualElementCallWidget` (properties and config: intent, encryption, notification
type), `generateWebviewUrl`, `makeWidgetDriver` (a driver that runs against a `Room` and a handle that passes
widget-API messages), `getElementCallRequiredPermissions`, and on `Room` `hasActiveRoomCall`,
`activeRoomCallParticipants` and `declineCall`; `RoomInfo` carries `hasRoomCall` and `activeRoomCallParticipants`.
It has no native LiveKit client.

The well-knowns on 2026-11-25: `linagora.com` lists a `livekit` focus with `livekit_service_url`
(`https://matrix-rtc.linagora.com`, the side service of web D387) and `livekit_base_url` (Meet). `stg.lin-saas.com`
and `twake.app` list only `livekit_base_url` (Meet), which is not a token service. None serves
`.well-known/element/element.json`.

## Decision
- **Element Call in a web view, driven by the SDK.** A call opens Element Call in a `WKWebView` full screen. The SDK's
  widget driver runs against the room with the capabilities `getElementCallRequiredPermissions` gives; a script
  injected at document start forwards the widget's `postMessage` traffic to the app, and the app posts the driver's
  answers back. No LiveKit SDK is added. Code: `MatrixData/Proxies/ElementCallProxy.swift`,
  `MatrixData/Discovery/ElementCallDiscovery.swift`, `Room/RoomCallViewModel.swift`, `Room/RoomCalls.swift`,
  `Room/CallKitReporter.swift`.
- **Offered only with a token service.** The call button and the active-call banner appear only when the account's
  well-known has a `livekit` focus with an `https` `livekit_service_url`. A focus with only `livekit_base_url` (Meet)
  keeps today's Meet link button (#92). On a plain Synapse with no `rtc_foci`, neither appears; call events from other
  clients still show in the timeline. This narrows ADR 0026's "a `livekit` focus" to the key Element Call reads.
- **Where Element Call comes from.** First `call.widget_url` in the server's `.well-known/element/element.json`, the
  key Element Web and Element X read; otherwise the build setting `TWAKE_ELEMENT_CALL_URL` (Info.plist
  `ElementCallURL`), `https://call.element.io` in Debug and Release. Only the web app's code comes from there: the
  widget parameters go in the URL fragment, which is not sent to that server, and the media goes to the focus of the
  user's own homeserver.
- **The call.** The header button reads "Start call" with no call in the room and "Join call" while one is active; a
  banner above the timeline shows a call in progress with its participant count and Join. Element Call is told the
  room kind (`startCall`/`joinExisting`, or the `…Dm` intents in a direct chat), encryption per participant in an
  encrypted room and none otherwise, its app-bar header, no screen sharing (a web view on iOS cannot share the
  screen), and to ring the room when it starts a call (`NotificationType.ring`), as web D-m rings every member. A
  member whose power level forbids `org.matrix.msc3401.call.member` is told "You may not join a call in this chat",
  as the web says.
- **CallKit.** The call is reported to CallKit as an outgoing video call (system call indicator, audio session in
  `videoChat` mode, ended from the lock screen or Control Center). Mute and hold from the system are refused, since
  the widget owns the microphone and camera. The app declares the `audio` background mode so the call's sound
  continues when the app goes to the background.
- **Leaving.** Hanging up in Element Call (`im.vector.hangup` or `io.element.close`), the close button, or ending
  from CallKit closes the screen and stops the driver. Element Call leaves the call itself through a delayed event,
  so a closed app is removed from the call by the server.

## Consequences
**Good.** Calls interoperate with the web and Element on the same MatrixRTC and LiveKit stack, with media encrypted
end to end in encrypted rooms, and without a native media stack in the app. The SDK already pinned does all the
Matrix work. Servers without a token service see nothing new.
**Costly.** Element Call is loaded from a web server at each call; until Twake hosts its own and announces it in
`element.json`, that is `call.element.io`. The call lives in the room's screen: leaving the room ends it (no picture in
picture yet). The web's Meet extras on a call (recording, captions, transcription, D30) are not offered.
**Alternatives rejected.** A native LiveKit client (`client-sdk-swift`): a second media stack, and the MatrixRTC
membership, key sharing and ring would be written in the app instead of by Element Call and the SDK. Shipping
Element Call's embedded build inside the app: Element Call is AGPL-3.0, which [ADR 0016](0016-source-licence-and-reuse-rule.md)
has not settled. Keeping the Meet link only: no interoperable call with the web.

## Left for later
1. **Ringing an incoming call** when the app is in the background or closed: the NSE reads
   `org.matrix.msc4075.rtc.notification` (`MessageLikeEventContent.rtcNotification` in the SDK) and hands it to the
   app through `CXProvider.reportNewIncomingVoIPPushPayload`, which needs a PushKit registration, the `voip`
   background mode and a decline through `Room.declineCall`. It touches the push extension and the pusher (ADR 0009,
   ADR 0017), so it is its own change: #222.
2. Picture in picture and keeping the call while browsing other chats: #223.
3. Twake hosting Element Call and announcing it in `.well-known/element/element.json`.
4. The Meet features of D30 (recording, captions, transcription) on an unencrypted call.
5. Trying a call between iOS and the web on `linagora.com`; the simulator has no camera.

## Out of scope
- **Screen sharing.** A `WKWebView` on iOS cannot capture the screen for a web page, and sharing it from the app
  would need a ReplayKit broadcast extension feeding a native LiveKit track, which this ADR rejects. Element Call is
  told to hide it.

## When to revisit
When the SDK gains a native call API, when Twake hosts Element Call, or when the push work above is planned.
