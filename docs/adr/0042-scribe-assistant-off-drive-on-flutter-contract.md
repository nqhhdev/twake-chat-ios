---
type: ADR
title: "ADR 0042: Keep Scribe and the assistant's suggestions off; build Twake Drive on Flutter's contract"
description: "Proposed: Scribe and the Twake Assistant's suggestions stay off because no server announces the assistant (Apple Writing Tools cover correct, improve and rephrase); attaching from Twake Drive follows the Flutter picker behind app.twake.chat.enable_twake_drive, in its own change."
tags: [adr, composer, assistant, drive, server-dependent]
status: draft
---
# ADR 0042: Keep Scribe and the assistant's suggestions off; build Twake Drive on Flutter's contract

**Status:** Proposed, 2026-11-26, from the project owner's direction of 2026-11-25; for the owner's review. Covers
issues #183, #190 and #175 (epic #112), as rows of [ADR 0026](0026-matrix-first-client-server-features.md). The
author's removal of a link preview (#185) is already decided by
[ADR 0035](0035-timeline-extras-formats.md) (off until the web defines its event format) and is not changed here.

## Context
The owner's direction of 2026-11-25, verbatim:

> "Max sure migrate 100% func in twake-on-matrix + twake-space-chat: If funcs depends on other server ( difference
> bettwen Matrix SDK) pls write ADR to enable or disable it."
>
> "My goal: This repo will be a new app chat no only Twake Chat"

- **Scribe (#183).** The web composer has a Scribe chip with the Twake Assistant's prompts (correct, improve,
  rephrase; `DECISION.md` D53), never in a private encrypted room unless its owner allows it (D73, D215, room state
  `app.twake.chat.scribe`). It needs the Twake Assistant service. No server announces that service: there is no
  well-known key, and the web learns it only from its deployment (`ASSISTANT_CREATOR_USER_ID`). The Flutter app has no
  Scribe. On iOS 18.1 and later, Apple Writing Tools already offer proofreading and rewriting in every text field,
  the composer included, on the device or Apple's Private Cloud Compute.
- **Assistant suggestions (#190).** The web invites the Twake Assistant into rooms and shows its suggestions (D74,
  D102, D128), trusting the assistant's device only when ToM attests its key (D212). The same service is needed, with
  the same lack of announcement. The Flutter app has none.
- **Twake Drive (#175).** As of 2026-11-26, twake-on-matrix `main` has a Drive picker (`lib/pages/drive_picker`,
  `lib/data/drive`): shown when the homeserver's well-known `app.twake.chat` has `enable_twake_drive: true` and an
  OIDC issuer; it signs in to the Twake SSO with PKCE, exchanges the ID token for a Drive (Twake Workplace) token,
  opens a Drive "intent" page to pick a file, and attaches the file or its link (web D36, D200). The upload limit
  comes from the homeserver.

## Decision
1. **Scribe: off.** No Scribe code ships. The composer keeps the system's Writing Tools, which need no Twake service
   and send nothing to one. A Scribe entry is built, behind a capability check, only once a server announces the
   assistant (a well-known key or a documented endpoint, ADR 0026 rule 3), and never in an encrypted room unless its
   `app.twake.chat.scribe` state allows it.
2. **Assistant suggestions: off**, for the same reason. Messages the assistant posts in a room still show as any
   member's messages; nothing else is drawn for them.
3. **Twake Drive: on Flutter's contract, in its own change.** The attachment menu shows "Add from Twake Drive" only
   when `app.twake.chat.enable_twake_drive` is `true` and the account's server has an OIDC issuer, read through
   `ServerCapabilities` ([ADR 0034](0034-server-capabilities-and-account-services.md)). The SSO refresh token goes in
   the Keychain ([ADR 0007](0007-shared-session-store-app-group.md)). Until that change merges, nothing is shown;
   other providers stay reachable through the Files app. Built in #175: `MatrixData/Drive/TwakeSSO.swift`,
   `WorkplaceAPI.swift`, `Proxies/TwakeDriveProxy.swift`, `Domain/Models/DrivePickPlan.swift`, and
   `Room/DrivePicking.swift` with `RoomViewModel+Drive.swift`.

## Consequences
**Good.** No Twake-only button appears on a plain Matrix server, and no text is sent to an assistant no server
names. Writing help still exists on iOS through the system. Drive follows the one contract another client already
ships.

**Costly.** Twake users miss Scribe's own prompts and the assistant's suggestions on iOS. Drive is not there
until its change lands.

**Alternatives rejected.** Calling the Twake Assistant from a build setting: it would hide a server dependency in
the binary and work on one deployment only.

## When to revisit
When a server announces the Twake Assistant; when the Drive change lands (this ADR's decision 3 then names its
code).
