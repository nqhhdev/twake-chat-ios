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

## Consequences
**Good.** A space made on iOS is the same on the web and in Flutter. **Costly.** The create body is the app's, not the
SDK's: a change of the web's body has to be copied here. The photo picker is a third copy (Room, Settings, ChatList),
since a feature cannot import another (ADR 0005).

## When to revisit
When the SDK's `CreateRoomParameters` takes initial state, send the request through it.
