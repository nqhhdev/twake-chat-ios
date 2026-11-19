---
type: Task
title: "Deferred Features"
description: "Flutter features ADR 0011 left out of v1, and which of them the code has built since."
tags: [roadmap, scope]
status: draft
---
# Deferred Features

**State:** open. [ADR 0011](../../docs/adr/0011-v1-scope-core-chat.md) (Accepted) defers every feature below, but the
code has built most of them since 2026-11-13, following the owner's direction of 2026-11-14 recorded in
[ADR 0023](../../docs/adr/0023-features-from-web-client-ux-from-best-messengers.md) (Proposed). The rule "No code for
a deferred feature in v1" in [Constraints](../engineering/constraints.md) therefore no longer matches the code. The
owner settles this through issue #65 (the ADR that replaces ADR 0011's scope) and #100 (the accepted gaps before an App
Store release).

Taken from the Flutter app's `lib/pages` and `lib/domain` at the baseline commit of
[ADR 0013](../../docs/adr/0013-flutter-baseline-and-feature-status.md). The list may be incomplete. Status checked
on 2026-11-19 against the source at `5745f8a` (`origin/main`); "Built" means the code exists, not that it was tried on
a device. Remaining work is tracked in the issues named in the last column (epic #112).

| Feature | Flutter location | Status in the code | Still open |
|---|---|---|---|
| Contacts and new private chat | `contacts_tab`, `new_private_chat`, `domain/contact` | Built (`c231163`): `Packages/Features/People/Sources/People/PeopleScreens.swift`, `PeopleRepository.startDirectChat`, ToM lookup in `Packages/MatrixData/Sources/MatrixData/Discovery/TwakeContactLookup.swift` | Invite by e-mail or phone: #95 |
| New group, invitations | `new_group`, `invitation_selection` | Built: `PeopleRepository.createGroup` (`b291944`); accept and decline in `RoomListRepository` (`264fb9c`) with the invitations header in `ChatListScreen.swift`; invite members in `RoomDetailsProxy.invite` | |
| Web invitation link | `invitation_link_web` (route `/chat/:matrixid`) | Not built as a page. The app opens `matrix.to`, `twake.chat://chat/…` and `matrix:` links (`Packages/Domain/Sources/Domain/Models/MatrixLink.swift`, `TwakeChat/TwakeChatApp.swift`) | Proposed for dropping (ADR 0013) |
| Search (rooms and in-room) | `search`, `chat_search` | Built: in-room search `Packages/Features/Room/Sources/Room/RoomSearch.swift` (`e0fe737`); chats, people and server messages in the chat list, `ChatListViewModel.searchMessages` (`14ac73e`) | Server search covers unencrypted rooms only: #94 |
| Spaces, folders | `space_home`, `domain/spaces`, `data/datasource_impl/folders` | Spaces built (`7b1e0fd`): `Packages/Features/ChatList/Sources/ChatList/Spaces.swift`, `SpacesProxy`. Folders not built | Folders: #106; `page_style`: #110 |
| Calls | `dialer`, `domain/video_call` | Not built | #92 |
| Forward and share extension | `forward`, `share` | Built: forward in `Packages/Features/Room/Sources/Room/PinnedAndForward.swift` (`79830da`); the `TwakeChatShare` target, `TwakeChatShare/ShareViewController.swift` (`7ce2cf5`, [Share Extension](../architecture/containers/share-extension.md)) | Share suggestions: #109 |
| Drive picker | `drive_picker`, `domain/drive` | Not built. The "+" menu opens the Files app, which reaches any file provider (`AttachmentPicking.swift`). In Flutter only on the unmerged branch `feat/tom-3-drive-sso-foundation` | #106 |
| Multiple accounts | `multiple_accounts` | Not built | #102 (ADR first; affects the session store layout) |
| Chat details, profile, roles | `chat_details`, `chat_profile_info`, `profile_info` | Built: `Packages/Features/Room/Sources/Room/RoomDetailsScreen.swift` (`c61691a`); member profile, roles, remove and ban in `MemberProfile.swift` (`e0fe737`) and `RoomDetails.swift`; own profile in Settings | Own name shown wrong: #82 |
| Public rooms | `public_rooms` | Built (`7b1e0fd`): `Packages/Features/ChatList/Sources/ChatList/PublicRooms.swift`, `PublicRoomsProxy` | |
| Stories, archive, app grid, personal QR | `story`, `archive`, `app_grid`, `personal_qr` | Archive built (`7b1e0fd`): `ArchivedChats.swift`, kept in the web's account data `app.twake.chat.archived_rooms` (`RoomArchive.swift`). Stories, app grid and personal QR not built | App grid: #106; personal QR: #105; stories: "not now" in ADR 0023 |
| Drafts, pinned messages, album sending | `chat_draft`, `utils/room_draft_storage.dart`, `domain/media_album`, `domain/services/message_splitter.dart` | Built: drafts through `TimelineRepository.loadDraft` and `saveDraft` (`264fb9c`), shown on the chat list row; pin and unpin in `MessageActions.swift`, `TimelineProxy.pinnedMessages` (`79830da`); several pictures are sent one by one and grouped as an album (`AttachmentPicking.swift`, `TimelineRows.swift`, `eff5cc2`) | To verify: whether the album matches Flutter's `media_album` format (ADR 0013 open point) |
| Media viewer, download, URL preview | `image_viewer`, `media_viewer`, `domain/preview_url` | Built: image viewer and Quick Look in `Packages/Features/Room/Sources/Room/MediaViews.swift` (`c61691a`), share from the message menu (`752e3c3`), link previews through `LinkPreviewProxy` (`6a5b223`) | Save to Photos without Quick Look: #107 |
| Device settings | `device_settings` | Built (`87924c5`): `Packages/Features/Settings/Sources/Settings/DevicesAndVerification.swift` lists, renames and signs out sessions (`DevicesProxy`, `POST /delete_devices`) | |
| Settings and app lock | `settings_dashboard`, `widgets/lock_screen.dart` | Built: Chat, Privacy & Security, Notifications, Data and Storage and About pages (`SettingsScreen.swift`, `9372597`); app lock in `TwakeChat/AppLock.swift` (`62b83b7`); contacts visibility through ToM (`TwakeContactLookup.swift`, `14ac73e`). App language not built | Language: #90; adding an e-mail or phone: #98; app lock on a device: #114 |
| ToM recovery words | `data/network/recovery_words` | Built ([ADR 0024](../../docs/adr/0024-recovery-key-kept-by-tom.md), web D14): `TomRecoveryVault` keeps the key on `/_twake/recoveryWords`, `DeviceUnlocker` unlocks the device after sign-in, Settings gives a new key to ToM | #81, #87, #120 |
| iPad layout | `chat_adaptive_scaffold` | Built: the Flutter breakpoints of [ADR 0022](../../docs/adr/0022-adaptive-layout-flutter-breakpoints.md) in `Packages/DesignSystem/Sources/DesignSystem/Layout/TwakeLayout.swift` (`9b0af5a`) and `TwakeChat/ChatShell.swift` | Check on an iPad: #103 |
| Localisation beyond the first language | `lib/generated`, `assets/l10n` | Not built: `TwakeChat/en.lproj` and `fr.lproj` hold one string, the encrypted-message push text | #90 |
