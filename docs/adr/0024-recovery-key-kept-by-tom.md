---
type: ADR
title: "ADR 0024: Keep the recovery key on ToM so a new device unlocks itself"
description: "Proposed: after sign-in the app reads the recovery key from ToM's /_twake/recoveryWords and verifies the device with it, or sets encryption up and gives ToM the new key; whoever controls ToM can read the encrypted history."
tags: [adr, e2ee, recovery, tom]
status: draft
---
# ADR 0024: Keep the recovery key on ToM so a new device unlocks itself

**Status:** Proposed, 2026-11-19, from the project owner's choice of that day ("ToM recovery words, full flow"); for
the owner's review. Answers open point 2 of [ADR 0017](0017-flutter-upgrade-keep-and-drop-lists.md) and widens the
Encryption row of [ADR 0011](0011-v1-scope-core-chat.md).

## Context
- [ADR 0011](0011-v1-scope-core-chat.md) limits recovery to a key the user types; ToM recovery words were deferred
  ([Deferred Features](../../.okf/backlog/deferred-features.md)).
- [ADR 0017](0017-flutter-upgrade-keep-and-drop-lists.md) open point 2: users updating from the Flutter app have never
  seen their key, because Flutter reads it from ToM during bootstrap (`tom_bootstrap_controller.dart`). Without ToM they
  type a key they do not have and lose their encrypted history.
- [ADR 0023](0023-features-from-web-client-ux-from-best-messengers.md) takes features from the web client. Its
  `DECISION.md` D14 ("The recovery key is kept by ToM, as Twake Chat does", decided 2026-10-05) stores the key on ToM
  with the Flutter endpoint and shape, so all clients share one key. Its use case is
  `src/application/useCases/unlockDevice.ts`; its vault is `src/adapters/tom/TomRecoveryVault.ts`.
- The pinned SDK ([ADR 0015](0015-pin-matrix-rust-components-swift-26-04-01.md)) creates the key and the secret storage
  in one call (`Encryption.enableRecovery`). It cannot make a key first and set up later, which the web client does to
  reserve the key on ToM before building anything.

## Decision
- **Endpoint.** `GET`, `POST` and `DELETE` on `<ToM>/_twake/recoveryWords`, body `{ "words": "<recovery key>" }`, with
  the Matrix access token as `Bearer`, byte for byte as Flutter and the web client send them (ADR 0017 table). ToM is
  found as today, through `t.server` in `.well-known` (`TwakeContactLookup.tomServer`). `GET` 404 means "no key";
  `POST` 409 means "ToM keeps another key", which ToM never replaces.
- **Unlock after sign-in.** Once the session is ready, after each sign-in and each launch while this device is not
  verified, the app runs one unlock, as web D14 does:
  1. Device already verified: nothing.
  2. ToM has a key: `recover` with it. An error other than a wrong key may mean another device is still finishing:
     try again for up to 20 s, then `recoverAndFixBackup`. A wrong key on an account with recovery disabled is a dead
     key: set encryption up (step 3) and replace the key on ToM (`DELETE` then `POST`).
  3. ToM has no key and the account has recovery disabled: `enableRecovery`, then `POST` the new key.
  4. ToM has no key and the account is set up: wait up to 20 s for another device to give ToM its key, then step 2.
  5. Anything else (wrong key, ToM down, no ToM): the user verifies as today (the room banner, Settings).
- **A key ToM did not keep is shown to the user.** When `POST` fails or answers 409 after this device set encryption
  up, the app shows the new key in the existing recovery-key sheet; it is never lost silently.
- **Settings.** "Set up chat backup" also gives the new key to ToM, so the next device unlocks itself.
- **Nothing is stored on the device.** The key read from ToM lives in memory for the unlock only;
  [ADR 0007](0007-shared-session-store-app-group.md) ("the recovery key is never persisted by this app") holds. The app
  never logs the key.
- **Matrix works without ToM.** A missing or failing ToM never blocks sign-in or sync; the app falls back to step 5.

## Consequences
**Good.** Users updating from Flutter, and anyone signing in on a new iPhone, read their encrypted history without
typing a key; iOS, Android and the web share one key.
**Costly.** Whoever controls ToM can read the encrypted history of the account (the cost web D14 accepted). Two brand
new devices of one account that set encryption up at the same moment can leave ToM with the key of the device that
lost: the SDK gives no way to reserve the key first. The losing device sees ToM answer 409 and shows its key to the
user, so the user still has a working key.
**Alternatives rejected.** `GET` only (ADR 0017's proposal): accounts set up on iOS would never get a key on ToM, so
the next device asks the user again. Keep the key in the Keychain as Flutter does: forbidden by ADR 0007.

## When to revisit
When the SDK can create a recovery key before setting the storage up (then reserve it on ToM first, as the web does),
or when the product moves to a server-side recovery the server cannot read.
