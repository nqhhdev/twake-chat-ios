---
type: ADR
title: "ADR 0012: Reuse the Flutter app's bundle identifier"
description: "The native app ships as app.twake.ios.chat, so it installs over the Flutter app instead of beside it."
tags: [adr, release, push, security]
status: draft
---
# ADR 0012: Reuse the Flutter app's bundle identifier

**Status:** Accepted by the project owner, 2026-11-11: the identifier, the first-launch cleanup and the release rule.

## Context
The Flutter Twake Chat app is published as `app.twake.ios.chat`. A native app can take the same identifier, and become
an update of that app, or a new one, and be a second app. The identifier decides the App Group, the Keychain group, the
URL schemes, the push registration and what happens to data already on a user's device.

Identifiers the Flutter app uses today (read from its Xcode project and entitlements):

| What | Value |
|---|---|
| App | `app.twake.ios.chat` |
| Notification Service Extension | `app.twake.ios.chat.nse` |
| Share extension | `app.twake.ios.chat.TwakeShareExtension` |
| App Group | `group.app.twake.ios.chat` |
| Keychain access group | `$(AppIdentifierPrefix)app.twake.ios.chat` |
| URL schemes | `twake.chat`, `matrix` |
| Associated domain | `links.twake.app` |
| Push app id sent to the gateway | `app.twake.ios.chat` in release builds, `app.twake.ios.chat.sandbox` otherwise |

## Decision
- The native app, its extension, App Group, Keychain group, URL schemes and push app ids use the values above.
- The native app's version and build numbers are always higher than the Flutter app's last release.
- The native app does not read the Flutter app's database or reuse its Matrix device. The encryption keys of that
  device live in the Flutter app's own store in another format; reusing the device id without them would break
  encryption. The user signs in again and gets a new device.
- **First launch after an update:** the app looks for the session the Flutter app left in the shared
  Keychain, uses it once to sign that old device out on the server (which also removes its pusher), then deletes the
  Flutter app's leftover files in the app and App Group containers and its Keychain items, including the stored recovery key.
- **Release rule:** a build is published to the public App Store only when the project owner accepts its
  feature gap against the Flutter app. Until then builds go to internal and TestFlight testers only.

## Consequences
**Good.** One app for users; the SSO callback, universal links and push gateway registration already exist; no new
server-side setup. **Costly.**
- The two apps cannot be installed together: a tester's TestFlight build replaces their Flutter app, and going back
  means reinstalling it and signing in again.
- Every updating user signs in again and must restore encryption with their recovery key or another device.
- Version 1 is core chat only ([ADR 0011](0011-v1-scope-core-chat.md)), so publishing it as an update would remove
  features, and the share extension, from existing users. Hence the release rule.
- Users on iOS 16 and 17 stop receiving updates ([ADR 0002](0002-ios-18-minimum-ios-26-styling.md)).
- Old data from the Flutter app stays on the device until the cleanup runs, so the cleanup must be tested.

**Alternatives rejected.** A new identifier: both apps side by side and no leftover data, but a second store listing,
new push and SSO registration, and users must move by hand. Migrating the Flutter session and keys: no supported path
between the two SDK stores.

## When to revisit
If testers need both apps installed at once (a separate internal identifier for debug builds could be added), or if a
supported way to migrate the Flutter session appears.
