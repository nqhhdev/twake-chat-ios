---
type: ADR
title: "ADR 0037: Keep contacts in the ToM address book and invite through ToM when the server enables it"
description: "Proposed: on a server announcing t.server, the Contacts tab lists, adds, renames and removes contacts in ToM's /_twake/addressbook; when app.twake.chat.enable_invitations is also on, phone contacts without an account are invited through /_twake/v1/invite and a sign-up link can be shared; the status comes from ToM, nothing is stored on the device."
tags: [adr, tom, contacts, invitations]
status: draft
---
# ADR 0037: Keep contacts in the ToM address book and invite through ToM when the server enables it

**Status:** Proposed, 2026-11-25, from the project owner's direction of that day; for the owner's review. Covers
issues #187 and #188, and applies [ADR 0026](0026-matrix-first-client-server-features.md) rows "ToM address book" and
"Invitation link and invitation status".

## Context
The owner's direction of 2026-11-25, verbatim:

> "Max sure migrate 100% func in twake-on-matrix + twake-space-chat: If funcs depends on other server ( difference
> bettwen Matrix SDK) pls write ADR to enable or disable it."
>
> "Pls auto and auto no need human review, I will review it after 100% func works well"

- Flutter keeps a per-user address book on ToM (`lib/data/network/contact/address_book_api.dart`,
  `add_contact_dialog.dart`): a name and a Matrix id, `POST /_twake/addressbook` with
  `{"contacts":[{"mxid","display_name"}]}`. ToM (`packages/tom-server/src/addressbook-api`) also serves
  `GET /_twake/addressbook`, `PUT` and `DELETE /_twake/addressbook/{id}`; adding an existing Matrix id is skipped.
- Flutter invites a phone contact without an account through ToM (`invitation_api.dart`): `POST /_twake/v1/invite`
  `{"contact","medium":"email"|"phone"}` sends an e-mail or SMS with a sign-up link; `POST /_twake/v1/invite/generate`
  returns `{link,id}`; `GET /_twake/v1/invite/{id}/status` returns the invitation. ToM also lists the sender's
  invitations (`GET /_twake/v1/invite/list`) and refuses every invitation call when `twake_chat.enable_invitations` is
  off, which its well-known announces as `app.twake.chat.enable_invitations`.
- [ADR 0029](0029-identity-server-for-email-and-phone.md) already invites by e-mail or phone with Matrix third-party
  invites, on any server with an identity server.
- A `ServerCapabilities` model is being added (#192); until it lands, the existing `t.server` lookup is read.

## Decision
1. **Detection.** The address book is shown when the well-known names `t.server`. Invitations are shown when it also
   has `app.twake.chat.enable_invitations` set to `true`; any other value, or a malformed `app.twake.chat`, means off
   and never hides the `t.server` features. Otherwise nothing is shown and no `/_twake` request is sent (ADR 0026
   rule 4). The answer is kept per signed-in user, so another account looks again.
2. **Address book.** The Contacts tab shows "My contacts" (active entries, sorted by name, filtered by the search
   text); a tap opens the chat. The "+" menu adds a contact (name and Matrix id, checked as `@local:server`, refused
   when already listed); swipe or long press edits the name or removes the contact. The Matrix id of an existing
   contact is not editable. Requests and bodies are Flutter's and ToM's, byte for byte (ADR 0017).
3. **Invitations.** When invitations are on, the Invite button of a phone contact without an account sends ToM's
   invitation (e-mail first, else phone in international form), as Flutter does, and shows "Invited". When they are
   off, it keeps ADR 0029's Matrix third-party invite. A typed e-mail or phone in the search keeps ADR 0029's
   behaviour (it creates the chat). The "+" menu creates an invitation link without a contact and opens the share
   sheet, and opens an Invitations page listing the user's invitations from `/invite/list` with their status (joined,
   opened, sent, expired; refreshable one by one through `/invite/{id}/status`). A 429 answer is shown as "too many
   invitations".
4. **Nothing on the device.** Invitation ids and statuses are read from ToM each time; unlike Flutter, the app keeps
   no local table of invitations per contact. The "Invited" mark lasts while the app runs.

## Consequences
**Good.** Contacts added on iOS show in Flutter and the web, and the other way round. A plain Matrix server sees no
Twake UI. No new local store, so nothing to clear at logout.

**Costly.** "Invited" on a phone contact is forgotten after a restart; the Invitations page is where the state lives.
Two invitation paths exist on Twake (ToM for phone contacts, Matrix third-party invites for a typed address), chosen
by what each flow did in Flutter.

**Alternatives rejected.** Storing invitation ids locally as Flutter does: a second source of truth that ToM's list
already answers. Using ToM's invitation for typed addresses too: it sends a sign-up link but creates no chat, unlike
the search flow users expect from ADR 0029.

## When to revisit
When #192's `ServerCapabilities` lands (move detection there); when ToM changes these endpoints; or when the owner
wants one invitation path on Twake.
