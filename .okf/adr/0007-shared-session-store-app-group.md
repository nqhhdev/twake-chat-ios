---
type: ADR
title: "ADR 0007: One session store shared by the app and the extension"
description: "The SDK store lives in the App Group container and tokens in a shared Keychain group, read by both processes."
tags: [adr, storage, push, e2ee, security]
status: draft
---
# ADR 0007: One session store shared by the app and the extension

**Status:** Accepted by the project owner, 2026-11-11.

## Context
To show the text of an encrypted message in a notification, the Notification Service Extension must decrypt it, which
needs the session and its keys. In the Flutter app the two processes use different SDKs and stores, so the session and
the recovery key are copied into the Keychain for the extension (that app's ADR 35), which widens what is stored.

## Decision
- The SDK's state, event-cache and crypto stores are created in the App Group container `group.app.twake.ios.chat`,
  in a directory of their own, apart from anything the Flutter app left there ([ADR 0012](0012-reuse-flutter-bundle-identifier.md)).
- Access token, refresh token, user id, device id and homeserver URL are stored in a Keychain access group shared by the
  app and the extension. Nothing secret goes into `UserDefaults`.
- The recovery key is never persisted by this app.
- Both processes open the store with the SDK's own cross-process locking. The way to enable it must be read from the
  pinned SDK version.
- The SDK store is the only database in v1. No SwiftData, Core Data or second cache.
- Sign-out deletes the store directory and the Keychain items.

## Consequences
**Good.** The extension decrypts with the real keys; one source of truth; less secret material stored.
**Costly.** Two processes on one store need the locking to be right; the extension's memory limit constrains what it may load.
**Alternatives rejected.** Copying keys to the extension: the weakness this avoids. A separate cache database: duplicates the SDK.

## When to revisit
If the extension exceeds its memory limit with the shared store, or when a feature needs data the SDK does not keep.
