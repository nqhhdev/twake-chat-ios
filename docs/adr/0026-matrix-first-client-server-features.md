---
type: ADR
title: "ADR 0026: A Matrix-first client; every non-Matrix server feature is detected, never assumed"
description: "Proposed: the app aims at full parity with twake-on-matrix and twake-space-chat on any Matrix homeserver; each feature that needs a Twake or other service is turned on only when the server announces it, and is hidden on a plain Synapse. Supersedes ADR 0011's v1 scope once accepted."
tags: [adr, scope, server, discovery, roadmap]
status: draft
---
# ADR 0026: A Matrix-first client; every non-Matrix server feature is detected, never assumed

**Status:** Proposed, 2026-11-25, from the project owner's direction of that day; for the owner's review. Once
accepted it supersedes the scope of [ADR 0011](0011-v1-scope-core-chat.md) and settles issue #65.

## Context
The owner's direction of 2026-11-25, verbatim:

> "Max sure migrate 100% func in twake-on-matrix + twake-space-chat: If funcs depends on other server ( difference
> bettwen Matrix SDK) pls write ADR to enable or disable it."
>
> "My goal: This repo will be a new app chat no only Twake Chat, it will be my own project and contribute directly to
> MAtrix clients."

Three records disagree about scope today:

- [ADR 0011](0011-v1-scope-core-chat.md) (Accepted, 2026-11-11) limits v1 to core chat and defers every other feature,
  and the constraint "No code for a deferred feature in v1" enforces it.
- [ADR 0023](0023-features-from-web-client-ux-from-best-messengers.md) (Proposed, 2026-11-14) takes the feature list
  from the web client and puts threads, calls, stories, emotes and folders "not now".
- The code on `origin/main` has built most deferred features since 2026-11-13 (see
  [Parity Matrix](../../.okf/backlog/parity-matrix.md)), so ADR 0011's constraint no longer matches the code.

Both reference clients assume a Twake deployment: the ToM server (`t.server` in `.well-known/matrix/client`, paths under
`/_twake/...`), the Twake push gateway, the Twake registration site, Meet, Twake Drive, the common settings, Scribe and
the Twake common proxy. A user of a plain Synapse or another homeserver has none of them. The app already behaves that
way in places: `TwakeContactLookup` and `TwakeMeet` (MatrixData `Discovery/`) read `t.server` and
`org.matrix.msc4143.rtc_foci` from the well-known and do nothing without them; `TomRecoveryVault` needs ToM
([ADR 0024](0024-recovery-key-kept-by-tom.md)). The rule is not written down, and each new feature decides it again.

## Decision
1. **Scope.** The app reaches parity with every user-facing feature of `twake-on-matrix` and `twake-space-chat`, as
   listed in the [Parity Matrix](../../.okf/backlog/parity-matrix.md). A feature leaves that list only by a decision
   recorded in this ADR's table (dropped) or a later ADR. This replaces ADR 0011's v1 scope; ADR 0023 still decides
   *where* a feature's behaviour and data format come from (web first, Flutter where the web has nothing) and how it
   looks.
2. **Matrix first.** A feature that the Matrix specification, an MSC the homeserver announces, or the device itself
   can deliver is built on that, for every server. The Twake service is used in addition only where it gives
   something Matrix cannot (the recovery key kept for the user, the ToM directory).
3. **Detected, never assumed.** A feature that needs a non-Matrix service is turned on only when one of these says
   the service is there, read once per session and on sign-in:
   - **Well-known**: `.well-known/matrix/client` keys `t.server` (ToM base URL), `app.twake.chat`
     (`support_contact`, `common_settings.application_url`, `enable_invitations`, `public_groups`, `web_url`) and
     `org.matrix.msc4143.rtc_foci` (call focus).
   - **`/_matrix/client/versions`**: `unstable_features` for an MSC that the homeserver must implement.
   - **Endpoint probe**: a documented capability endpoint of the service (for example `GET /v1/modules` of the Twake
     common proxy), never a probe by trial of a user action.
   - **Build configuration**: a URL in the build settings (`TWAKE_*` in `project.pbxproj`, read from `Info.plist`) for
     a service the homeserver cannot announce. An empty value turns the feature off.
4. **Absent means hidden.** When the check fails, the entry point (button, menu item, settings row) is not shown, and
   no request is sent to a Twake path. There is no error, no disabled control and no placeholder. Data written by
   another client for that feature (a call event, a folder in account data) is still shown read-only when Matrix
   carries it.
5. **The Twake build** (the bundle id of [ADR 0012](0012-reuse-flutter-bundle-identifier.md)) sets every Twake build
   setting, so on a Twake server it behaves as the Flutter app does. A build without them is a plain Matrix client.
6. **Per feature:**

| Feature | Needs | Detection | On a plain Synapse | Twake build default |
|---|---|---|---|---|
| Contacts lookup (ToM directory) | ToM `POST /_twake/identity/v1/lookup/match` | well-known `t.server` | Matrix user directory only (`/user_directory/search`) | On (built) |
| Contacts visibility (who sees e-mail and phone) | ToM `/_twake/v1/user_info/{id}/visibility` | `t.server` | Settings row hidden | On (built) |
| Recovery key kept by the server | ToM `/_twake/recoveryWords` | `t.server` | The user keeps and types the recovery key (Matrix secret storage) | On (built, ADR 0024) |
| ToM address book: add and edit a contact | ToM `/_twake/addressbook` | `t.server` | Hidden | On |
| Invitation link and invitation status | ToM `/_twake/v1/invite`, `/invite/generate` | `t.server` and `app.twake.chat.enable_invitations` | Hidden; e-mail invites go through the identity server (Matrix 3pid, ADR 0029) | On |
| Language from the common settings | ToM `user_info` `language` | `t.server`, field present | Device language | On |
| Analytics with consent | ToM `/_twake/v1/analytics/events` | `t.server` and build setting on | Off, nothing collected, no consent prompt | Off until the owner turns it on |
| Push notifications | A push gateway with the app's APNs credentials | Build setting `TWAKE_PUSH_GATEWAY_URL` | Works: the gateway does not depend on the homeserver ([ADR 0009](0009-push-gateway-and-nse-decryption.md)) | On (Twake gateway) |
| Sign up | Twake registration site | Build setting `TWAKE_REGISTRATION_URL` | Matrix `/register` when the server offers it (`HomeserverDiscovery.registrationSupported`), else none | On (built, [ADR 0021](0021-sign-in-as-the-flutter-app.md)) |
| Twake Welcome screen and Twake ID | Twake registration site | Build setting | Starts on the homeserver picker | On (built) |
| Delete account | Common settings page, else Matrix | `app.twake.chat.common_settings.application_url` | Matrix `/account/deactivate` with user-interactive auth | On |
| Help and support chat | Support URL; support contact | A new build setting for the support URL; `app.twake.chat.support_contact` | Help row only if the build sets a URL; no support chat | On |
| Calls: Meet link and call events | Meet; ToM `/_twake/v1/video_call/rooms` | `rtc_foci` and `t.server` | Call events shown; no call button | On (built, #92) |
| Calls in the app (MatrixRTC, MSC3401, MSC4143, MSC4195) | A LiveKit focus and its token service | `rtc_foci` with a `livekit` focus | Hidden unless the server announces a focus | On when Twake's focus is announced |
| Twake Drive picker | Twake Drive and the Twake SSO token exchange | Build setting for the Drive URL | Hidden; "+" › Files reaches every file provider | Off until a Drive picker contract exists for iOS |
| App grid (other Twake apps) | A list of Twake apps | Build setting (bundled list) | Hidden | On |
| Public web page of a channel | twake-chat-side-service | A new build setting for the side service URL (the web's `PUBLIC_PAGES_URL`) | Hidden; the matrix.to link is still copied | Off until the owner asks |
| Twake Assistant in rooms (suggestions) | The Twake assistant service | Not announced today | Hidden | Off |
| Scribe in the composer (correct, improve) | Twake Assistant (Scribe) | Build setting; never in an encrypted room (web D73, D215) | Hidden | Off until the owner asks |
| Translate a message | None: Apple's on-device Translation framework | Device support | Works | On |
| Transcribe a voice message | None: on-device speech recognition | Device support | Works, also in encrypted rooms (nothing leaves the device) | On |
| Scheduled send | Homeserver delayed events, MSC4140 | `/versions` `unstable_features` `org.matrix.msc4140` | Hidden | On when announced |
| GIF picker | Twake common proxy (Klipy) | Decided in ADR 0028 | Decided in ADR 0028 | Decided in ADR 0028 |
| E-mail and phone (3pid) invites and settings | Identity server | Decided in ADR 0029 | Decided in ADR 0029 | Decided in ADR 0029 |
| QR verification and personal QR | Matrix only; SDK support | Decided in ADR 0030 | Same as Twake | Decided in ADR 0030 |

7. **Not server-specific.** These are Matrix and need no detection beyond what the SDK does: URL previews
   (`/_matrix/client/v1/media/preview_url`, never in encrypted rooms, web D211), the identity server, spaces, public
   rooms, threads, polls, receipts, push rules. The app relies on these MSCs; each is read in its stable and unstable
   names where both exist:
   - Simplified sliding sync (MSC4186), required by the SDK ([ADR 0003](0003-matrix-rust-sdk.md)).
   - Polls, MSC3381; voice messages, MSC3245 with extensible audio MSC1767.
   - Bot commands, MSC4332 (`org.matrix.msc4332.command`).
   - MatrixRTC call membership, MSC3401; call ring, MSC4075; call focus in the well-known, MSC4143.
   - Authenticated media, MSC3916 (`/_matrix/client/v1/media`).
   - Custom emotes and sticker packs, MSC2545 (`im.ponies.*`), when built.
   - Delayed events, MSC4140, when built (scheduled send).
8. **Dropped**, kept out of the matrix's open work: stories (no entry in Twake's settings, ADR 0023), the Flutter web
   invitation page (`invitation_link_web`: matrix.to links open in the app), app themes, chat wallpaper, text size and
   the 12/24-hour clock (iOS system settings), "Back to Twake Space" and the embedded page (web only), resizable panes
   (iPad split view), web push (APNs instead).

## Consequences
**Good.** One rule for every server feature: a plain Synapse user sees a complete Matrix client with no dead buttons,
and a Twake user sees the Flutter app's features. The project can be offered to the wider Matrix community without
Twake services. **Costly.** Each Twake feature carries a detection check and a test for both cases (present, absent);
the well-known is read once more per session. **Alternatives rejected.** Twake-only client: contradicts the owner's
goal. Separate Twake and Matrix builds with compile-time flags for everything: two apps to test; build settings are
kept only for services the homeserver cannot announce. Probing Twake paths and hiding on a 404: sends the user's token
to paths of an unknown server.

## When to revisit
When a Twake service gains a standard announcement (a well-known key or an MSC), or when the owner accepts, rejects or
reorders a row of this table. The owner's acceptance also changes ADR 0011's status to "Superseded by ADR 0026".
