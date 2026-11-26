---
type: ADR
title: "ADR 0039: Several accounts, one store and one Keychain item each, one account on screen"
description: "Proposed: each account gets its own SDK store directory and Keychain item, listed in an accounts file in the App Group; the signed-in single account stays where it is; pushes find their account by the client identifier they already carry; one account runs on screen, the others reach the user through push."
tags: [adr, accounts, storage, push, e2ee, security]
status: draft
---
# ADR 0039: Several accounts, one store and one Keychain item each, one account on screen

**Status:** Proposed, 2026-11-25, for issue #102 (epic #112). Decided without the owner, under the owner's direction of
2026-11-25: « Pls auto and auto no need human review, I will review it after 100% func works well » and « Dont ask me
anything keep do it until I back ». The owner accepts or changes it at review.

## Context
- The Flutter app signs in several accounts (`lib/pages/multiple_accounts/multiple_accounts_picker.dart`); its ADR 0032
  fixes a race where the second account's store was named before the login answered. The web client builds the same
  feature (`twake-space-chat` `docs/multi-account-plan.md`, decision D373): the account key is the user id, there is no
  privileged account, one account is on screen and the others keep notifying, at most 5 accounts.
- This app holds one session ([ADR 0007](0007-shared-session-store-app-group.md)): one SDK store directory
  `Library/Application Support/TwakeChat/SDK` in the App Group and one Keychain item (service `app.twake.ios.chat`,
  account `session`), read by the app and by the Notification Service Extension
  ([ADR 0009](0009-push-gateway-and-nse-decryption.md)) under the SDK's cross-process lock.
- The SDK's client is built on one store directory and must be given it before the login answers with the user id.
- Every push already carries `pusher_notification_client_identifier`, the SHA-256 of the user id in hex, from the
  pusher's `default_payload` (`PusherProxy.defaultPayload`, kept byte for byte as the Flutter app sends it, ADR 0017).
- `POST /pushers/set` with `append: false` (the SDK's `setPusher` has no `append`, and the Flutter app sends `false`)
  deletes the pushers of other users with the same `app_id` and `pushkey`. Two accounts of one homeserver on one device
  share the APNs token, so the second sign-in deletes the first account's pusher.
- Users updating from a single-account build are signed in and must stay signed in, with their store untouched.

## Decision
### Store layout
- An account lives in a **slot**: an opaque id that names its store directory and its Keychain item. The slot is
  chosen before sign-in; the user id is only known once the login answers (Flutter ADR 0032), so nothing is named after
  the user id.
- The **legacy slot** is the single-account layout, unchanged: store `TwakeChat/SDK`, Keychain account `session`.
  Any other slot is a lower-case UUID: store `TwakeChat/Accounts/<slot>/SDK`, Keychain account `session.<slot>`. No
  slot's store is inside another's, and none is inside the Flutter trees the first-launch cleanup deletes (ADR 0017).
- The accounts are listed in `TwakeChat/accounts.json` in the App Group container (AppShared `AccountRegistry`): each
  account's user id and slot, and the account on screen. It holds no secret (ADR 0007 keeps tokens in the Keychain), so
  the extensions read it without the Keychain.
- A sign-in uses the legacy slot while no account holds it, otherwise a fresh slot. A sign-in that ends on an account
  already listed is refused ("already added"): the new device is signed out and its slot deleted. At most **5**
  accounts, as on the web.

### Migrating the single-account store
- At launch, when the accounts file is missing or empty and the legacy Keychain item holds a session, that session is
  listed as the first account in the legacy slot, and made active. No file moves, no Keychain item is rewritten, the
  session is not restored to migrate it: an update never signs anyone out and the extension keeps reading the same
  store. A launch where the Keychain cannot be read lists nothing and migrates at the next launch.

### Keychain
- One generic-password item per account, in the shared access group, service `app.twake.ios.chat`, account `session`
  (legacy slot) or `session.<slot>`; same accessibility (`AfterFirstUnlockThisDeviceOnly`) and contents as before. Token
  refreshes write the item of their own account only.

### Running accounts
- One account is on screen and runs a client and sync in the app. Switching stops the current account's client and
  builds the other's (a new composition of its repositories); its unsent work stays in its own store. The other
  accounts do not sync in the background: their messages reach the user through push, as the web's background
  accounts do through their workers. This keeps one SDK client in the app's memory.
- Each account keeps its own device, keys, recovery and server capabilities (#192 is per session, so it follows the
  account on screen). Services of the Twake deployment are never given another account's token (ADR 0026).

### Push, the extension and the badge
- Each account registers its own pusher with the same APNs token and the same `default_payload` shape. Pushers are set
  with `append: true` (a direct `POST /pushers/set`, since the SDK's call cannot set it), so one account never deletes
  another's pusher. Sign-out deletes only that account's pusher.
- The Notification Service Extension reads `pusher_notification_client_identifier`, finds the account whose user id
  hashes to it in the accounts file, and opens that account's slot under its own lock name `nse`. A push with no
  identifier uses the account on screen (a push from a pusher registered before this change); a push whose identifier
  matches no account shows nothing.
- With more than one account, a notification names its account: the account's user id follows the subtitle the
  extension writes (`Alice · @me:server`, or the user id alone in a direct chat). Every notification carries the
  account's user id in `userInfo["user_id"]`; a tap, Reply or Mark as read switches to that account first.
- The badge is the sum of every account's last `unread_count`. The extension keeps each account's count in the App
  Group's `UserDefaults` (`badge.<slot>`, a number, not a secret) and sets the sum; the app writes the count of the
  account on screen when it goes to the background, and removes an account's count when it signs out.

### Share extension
- The share extension stays session-less (it copies the items and opens the app). A share suggestion names its account
  in the `INPerson` that is the user (`isMe`), as its custom identifier: the sender of the suggestion the app donates
  when the user sends, the `isMe` recipient of the one the extension donates for a notification. The conversation
  identifier stays the room id. `serviceName` is not used: the system may show it, and it names a service, not an
  account. The share extension writes the account into the shared items, and the app switches to it before opening the
  room. Without a suggestion, the chat picker carries the account menu, so the user can pick the account first; the
  pending share follows the switch.

### Signing out of one account
- Sign out ends that account only: its pusher, its device on the server, its store directory, its Keychain item, its
  badge count and its share suggestions are removed, and it leaves the accounts file. The next listed account comes on
  screen; with none left, the sign-in screen shows. Signing out of every account is signing out of each in turn.
- An account the server signed out (session expired) is removed the same way, and the app tells the user which.

## Consequences
**Good.** Updating users keep their session and their store with no migration risk; the extension decrypts for every
account with each account's own keys; the push payload and the pusher fields do not change; accounts of one homeserver
no longer delete each other's pushers.
**Costly.** Only the account on screen syncs, so its unread counts are the only live ones; the other accounts' counts
come from their last push. Switching costs a client start. The legacy slot keeps a different path shape from the others
for good. `append: true` keeps a pusher of an account that was removed without reaching its server until the server
drops it.
**Alternatives rejected.**
- Moving the single-account store into `Accounts/<id>`: a move while the extension may hold the store lock, for no gain.
- Naming stores and Keychain items after the user id: the client needs its store before the user id is known (Flutter
  ADR 0032).
- A client per account syncing in the background: N times the memory and battery for counts push already gives.
- Listing accounts in `UserDefaults` or the Keychain: a file is readable by every process, easy to test, and holds no
  secret.
- Routing pushes by a new payload key: the client identifier is already in every push; a new key would need a
  gateway change and break the Flutter byte-for-byte rule.

## When to revisit
If users need live unread counts of every account while the app is open, if the SDK gains a way to share one client
across accounts, or when the SDK's `setPusher` gains `append`.
