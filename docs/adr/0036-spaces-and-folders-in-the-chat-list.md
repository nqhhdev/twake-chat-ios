---
type: ADR
title: "ADR 0036: Create spaces and keep chat folders as the web and Flutter do"
description: "Proposed: spaces and sub-spaces are created with the web's /createRoom body; chat folders use the shared app.twake.chat.folders account data and u.<name> room tags; the public page link stays off; the chat preview opens from its menu."
tags: [adr, chat-list, spaces, folders]
status: draft
---
# ADR 0036: Create spaces and keep chat folders as the web and Flutter do

**Status:** Proposed, 2026-11-25, for #177, #176, #189 and #132 (epic #112).

## Context
- The web creates spaces and sub-spaces with its own `/createRoom` body (`buildCreateRoomOptions`,
  `src/adapters/matrix/MatrixRoomManagement.ts`); Flutter has `new_space`. iOS could add a channel to a space only.
- The pinned SDK's `CreateRoomParameters` (26.04.01) has `isSpace` but no initial state, so it cannot name the parent
  (`m.space.parent`) or give a sub-space the `restricted` join rule the web gives it.

## Decision: creating a space (#177)
- "New Space" is in the chat list's More menu, beside Mark All as Read: name, description, picture and Public. "New
  Sub-space" is in a space's Add menu, beside New Channel, for people who may edit the space (`editableSpaces`).
- The request is the web's body, built in Domain (`NewSpace.createRoomBody`) and sent to `/createRoom` with the
  client-server API: `creation_content.type` `m.space`; `private_chat` preset, or `public_chat` with `visibility`
  `public` when Public is on; the web's power level overrides (members send call membership, bot commands, poll answers,
  thread resolution and assistant consent; only an owner publishes the public page); the picture, uploaded first, as
  initial `m.room.avatar`. A sub-space adds `m.space.parent` (canonical, `via` the parent's server and the user's),
  and the `restricted` join rule for the parent's members unless it is public; the parent then gets `m.space.child`
  through the SDK (`addChildToSpace`).
- Spaces are created in the clear, as the web creates them; nothing is posted in a new space.
- The new space opens; a new sub-space appears in its parent's page.

## Decision: chat folders (#176)
- Folders are stored as Flutter and the web store them, so the three clients share them: the global account data
  `app.twake.chat.folders` (`{"folders": [...]}`, each a built-in `{builtin, name?, emoji?, color?, hidden?}` or a
  user folder `{name, emoji?, color?, include?, exclude?}`), and the room tag `u.<name>` on each chat picked one by one
  (Flutter `folders_content.dart`, web `src/domain/folders.ts`). A chat is in a folder when it is not in `exclude`, and
  it is tagged or its kind (direct, group, broadcast, bot) is in `include`; spaces are in no folder.
- Writing keeps what this client does not know: unknown keys of a folder and built-ins of a newer client stay, as
  Flutter's `writeFolders(current:)` does. What is saved is the folders shown, then the built-ins not shown, hidden.
- The pinned SDK reads no custom room tag, so the app reads them all in one request: a `/sync` with a filter that
  keeps only the folders account data and each joined room's `m.tag` (`timeout=0`, no timeline, no state). It runs when
  the chat list opens and when the app comes back to the foreground. Tags are written with
  `PUT`/`DELETE /user/{userId}/rooms/{roomId}/tags/u.<name>`; the account data through the SDK.
- One chip per user folder follows the list's filters, in the saved order; the `+` chip creates one. A folder's chip
  menu edits, moves it left or right among the folders, or deletes it (asking first; its chats stay, their tags go).
  The editor has a name, an emoji, the kinds it takes in and the chats, ticked one by one; saving follows Flutter's
  `planEdit`: a ticked chat of a kind not taken in gets the tag, an unticked one of a kind taken in is excluded, a
  rename moves the tags. A chat's long-press menu has a Folders submenu to add it or take it out.
- The built-in folders (unread, broadcasts, directs, spaces, favourites) are kept as read and written back, but the iOS
  chips stay the app's own filters: renaming, hiding or moving a built-in on another client does not change them here.
  Colours are kept, not shown.

## Decision: the public web page link (#189)
- Not built. ADR 0026 keeps the public page of a channel off until the owner asks: it needs twake-chat-side-service and
  a build setting for its URL (the web's `PUBLIC_PAGES_URL`), and no deployment of that service is known for this app.
  Building the switch and Copy Public Link behind an empty setting would ship code no build can run (ADR 0011's rule
  against code for a deferred feature), so #189 stays open and the channel info keeps copying the matrix.to link.
- New spaces already carry what the web needs to publish a room later: only an owner may send
  `app.twake.chat.public_page` (power level 100).

## Decision: the chat preview (#132)
- PR #154 built the preview: a long press, or a secondary click with a pointer, shows the room's latest messages above
  the menu, read-only and newest last; it sends no read receipt; it closes its timeline when the menu closes; an
  undecryptable message shows the timeline's placeholder; spaces and invitations keep the plain menu; the row has a
  hover effect.
- What #132 still asks is that a tap on the preview opens the chat, as in Messages. SwiftUI's
  `contextMenu(menuItems:preview:)` gives no action for a tap on the preview: it only closes the menu. The menu now
  starts with Open, which opens the chat as a tap on the row does.
- A tap on the preview itself needs `UIContextMenuInteraction` (its `willPerformPreviewActionForMenuWith`) around the
  row, which would replace SwiftUI's list row menu and swipe actions with a UIKit bridge. That is left for the owner to
  decide; #132 stays open for it.

## Consequences
**Good.** A space made on iOS is the same on the web and in Flutter; a folder made on one client shows on the others.
**Costly.** Reading tags costs one filtered `/sync` when the list opens and on each return to the foreground, and a
folder changed on another client shows after that.  The create body is the app's, not the
SDK's: a change of the web's body has to be copied here. The photo picker is a third copy (Room, Settings, ChatList),
since a feature cannot import another (ADR 0005).

## When to revisit
When the SDK's `CreateRoomParameters` takes initial state, send the request through it.
