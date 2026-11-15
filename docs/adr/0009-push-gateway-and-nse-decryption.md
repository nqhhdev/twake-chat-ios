---
type: ADR
title: "ADR 0009: Push through the existing gateway, decrypted in the extension"
description: "The app registers an APNs pusher on the homeserver via the Twake push gateway; the extension fetches and decrypts the event."
tags: [adr, push, e2ee]
status: draft
---
# ADR 0009: Push through the existing gateway, decrypted in the extension

**Status:** Accepted by the project owner, 2026-11-11.

## Context
Matrix delivers push through a push gateway that the homeserver calls; Twake runs one (Sygnal) and the Flutter app is
built with its URL. For encrypted rooms the server cannot read the message, so the push carries only identifiers and the
device must fetch and decrypt the event.

## Decision
- After sign-in the app asks for notification permission, obtains the APNs device token and registers an HTTP pusher on
  the homeserver pointing at the gateway URL from build configuration. The pusher's app id is `app.twake.ios.chat` in
  release builds and `app.twake.ios.chat.sandbox` otherwise, the ids the Flutter app already uses
  ([ADR 0012](0012-reuse-flutter-bundle-identifier.md)).
- The pusher asks for identifiers only (room id and event id), never message content.
- The push is a visible, mutable notification so the system starts the
  [Notification Service Extension](../../.okf/architecture/containers/notification-service-extension.md), which fetches and
  decrypts the event through the SDK's notification client and rewrites the text.
- If decryption fails or time runs out, the notification shows a generic text; it never shows ciphertext or nothing.
- Sign-out removes the pusher.

## Consequences
**Good.** Message content never passes through Apple or the gateway; reuses existing infrastructure.
**Costly.** Depends on the extension finishing within the system's limits. **Alternatives rejected.** Server-rendered
content: impossible for encrypted rooms and leaks content otherwise. Background sync on silent push: unreliable on iOS.

## Open points
- The pusher format the Flutter app registers is a build setting there; confirm it asks for identifiers only before
  reusing the gateway configuration unchanged.

## When to revisit
If Apple changes extension limits, or when calls need VoIP push.
