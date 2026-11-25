---
type: ADR
title: "ADR 0029: Find and invite people by e-mail or phone through the account's identity server"
description: "Proposed: e-mail and phone lookups, phone-contact matching and third-party invites use the Matrix identity service API of the server named by account data or .well-known m.identity_server (ToM on Twake), only after the user accepts its terms and only with sha256 hashes; with no identity server the feature is hidden."
tags: [adr, identity-server, contacts, invites, privacy, tom]
status: draft
---
# ADR 0029: Find and invite people by e-mail or phone through the account's identity server

**Status:** Proposed, 2026-11-25, from the project owner's direction of that day; for the owner's review. Covers issues
#95 (invite by e-mail or phone, phone contacts) and #98 (add a phone number in Settings). It applies the
server-dependent rule of ADR 0026 (Proposed, in review at the time of writing).

## Context
The owner's direction of 2026-11-25, verbatim:

> "Max sure migrate 100% func in twake-on-matrix + twake-space-chat: If funcs depends on other server ( difference
> bettwen Matrix SDK) pls write ADR to enable or disable it."
>
> "My goal: This repo will be a new app chat no only Twake Chat"

- The Flutter app finds people by e-mail or phone with ToM's `POST /_twake/identity/v1/lookup/match` and the
  federated identity service (`lib/modules/federation_identity_lookup/`: `account/register`, `hash_details`,
  `lookup`), reads the phone's contacts, and invites people without an account with ToM's `POST /_twake/v1/invite`
  (`lib/data/network/invitation/invitation_api.dart`), which sends a Twake sign-up link. The web client has no e-mail
  invite; it only reads `m.identity_server` from the well-known (`src/domain/twakeServices.ts`).
- ToM is itself a Matrix identity server: `packages/matrix-identity-server` serves `/_matrix/identity/v2/terms`,
  `account/register`, `hash_details`, `lookup` and `store-invite`, and ToM's well-known announces it under
  `m.identity_server`.
- The Matrix specification gives every client the same tools on any server: the identity service API v2 (terms,
  OpenID registration, hashed lookup, `store-invite`), third-party invites (`POST /rooms/{id}/invite` and
  `invite_3pid` in `/createRoom`, both with `id_server` and `id_access_token`), and adding a phone to the account
  (`/account/3pid/msisdn/requestToken`, the code sent to the returned `submit_url`, then `/account/3pid/add` with
  User-Interactive Authentication). The pinned SDK (ADR 0015) exposes none of these, so they go over HTTP with the
  session's token, as the e-mail flow in `AccountSettingsProxy` already does.
- Uploading address-book data is the most privacy-sensitive thing the app does: a contact never agreed to it.

## Decision
1. **Which identity server.** The account data `m.identity_server` wins: a `base_url` there is used, and a `null`
   `base_url` means the user chose none. Without that event, the homeserver's `.well-known/matrix/client`
   `m.identity_server.base_url` is used. Only an `https` URL is used. On a Twake server this is ToM; nothing is
   special-cased for Twake.
2. **No identity server, no feature.** When neither names a server, or the server does not answer its terms, or does
   not offer the `sha256` lookup algorithm, the e-mail and phone rows in search, the invite by e-mail and the phone
   contacts section are not shown (ADR 0026 "absent means hidden"). Search by name and Matrix id still works.
   Adding an e-mail or phone in Settings does not depend on this: it is homeserver API, shown when the
   `m.3pid_changes` capability allows it.
3. **Consent first.** Before the first lookup, invite or contact upload, the app shows the server's name and its
   terms (`GET /_matrix/identity/v2/terms`, in the user's language, then English) and asks the user to accept. Only
   on acceptance does it register (OpenID token from `/user/{id}/openid/request_token` to `account/register`), post
   the accepted URLs to `/terms`, and record them in the `m.accepted_terms` account data, so other devices and
   clients do not ask again. Not now sends nothing. A server without policies needs no acceptance.
4. **Phone contacts.** Reading the address book needs the system permission (purpose string
   `NSContactsUsageDescription`), asked only when the user taps "Find people from your contacts". The addresses are
   normalised (e-mail lowercased; phones to E.164, a national number taking the calling code of the device's region,
   and skipped when the region is unknown), hashed per the spec (`sha256` of `"<address> <medium> <pepper>"`,
   unpadded URL-safe base64), and sent in batches of 500. Plain-text lookup (`none`) is never used. Nothing is
   stored: matches live in memory while the Contacts tab is open, and the identity server token stays in memory.
5. **Invites.** A looked-up address with an account becomes that Matrix user: a direct chat or a normal invite. An
   address without one is invited as a third party: in an existing room with `POST /rooms/{id}/invite`, in a new
   group or Broadcast right after creation, and as a new encrypted direct chat with `invite_3pid`. E-mail and phone
   (`msisdn`) are both offered; the identity server sends the invitation.
6. **ToM's own invitation link** (`/_twake/v1/invite`, `/invite/generate`) is not used here. It sends a Twake
   sign-up link rather than a room invitation, and ADR 0026 lists it as its own Twake-only row.

## Consequences
**Good.** One code path works on Twake, matrix.org and any homeserver with an identity server, and does nothing
without one. Lookups follow the spec's privacy rules: hashed addresses, explicit terms, an explicit permission tap.
The Settings phone flow and the e-mail flow share one User-Interactive Authentication step.

**Costly.** Phone numbers stored without a country code match only when the device's region is in the app's short
calling-code table (no libphonenumber). A direct chat created by a third-party invite is not added to `m.direct`
under the address, so the room shows as a group until the person joins. The identity server sees the hashes and the
inviter's identity; a server that rotates its pepper costs one extra request.

**Alternatives rejected.** ToM `lookup/match` and `/_twake/v1/invite` only: works only on Twake, against ADR 0026.
Lookup with the `none` algorithm when `sha256` is missing: sends contacts in clear text. Uploading the address book
in the background at first launch: no consent from the user. A bundled phone-number library: a new dependency for one
normalisation step.

## When to revisit
When the pinned SDK exposes identity-server or third-party-invite calls; when the specification deprecates identity
servers; when the owner wants ToM's invitation link or a full phone-number library; or when a server
needs `m.direct` entries for third-party invites.
