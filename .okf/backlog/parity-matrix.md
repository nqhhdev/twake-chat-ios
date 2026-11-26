---
type: Task
title: "Parity Matrix"
description: "Every user-facing feature of twake-on-matrix and twake-space-chat, its iOS state with file evidence, the server it needs and the issue that tracks it."
tags: [roadmap, scope, parity, server]
status: draft
---
# Parity Matrix

**State:** open. Checked on 2026-11-25 against `origin/main` at `39cef02` (PR #168 merged). Flutter reference:
`twake-on-matrix` at `9c769f877` (`lib/pages`, `lib/domain`, `lib/data/network`, `settings_dashboard`). Web reference:
`twake-space-chat` at `ad2e91a7` (`docs/implementation-plan.md` phases, `DECISION.md` entries). Scope and the
server rule: [ADR 0026](../../docs/adr/0026-matrix-first-client-server-features.md) (Proposed). Epic: #112.

"Built" means the code exists on `origin/main`, not that it was tried on a device. Paths are relative to the repository
root; `Room/`, `ChatList/`, `Settings/`, `People/` and `Authentication/` mean `Packages/Features/<name>/Sources/<name>/`,
`MatrixData/` means `Packages/MatrixData/Sources/MatrixData/`, `Domain/` means `Packages/Domain/Sources/Domain/`.

Server: **Matrix** (spec or an MSC, any homeserver), **ToM** (Twake's `/_twake` server named by `t.server`),
**Twake** (another Twake service or build setting), **Device** (Apple framework, no server).

## Sign-in and account

| Feature | Flutter | Web | iOS | Server | Issue |
|---|---|---|---|---|---|
| Twake Welcome, Twake ID through the registration site | `twake_welcome`, `sign_up` | — | Built: `Authentication/Welcome/`, `SignInConfiguration.swift` | Twake (build setting) | — |
| Company server: picker, discovery, SSO, password fallback | `homeserver_picker`, `connect`, `login` | Phase 1 | Built: `Authentication/HomeserverPicker/`, `Connect/`, `PasswordLogin/`, `MatrixData/Discovery/HomeserverDiscovery.swift` | Matrix | — |
| SSO sign-out | `settings` logout | Phase 1 | Built: `SignedInViewModel.swift` (issuer `?logout=1`) | Matrix | — |
| Multiple accounts | `multiple_accounts` | `docs/multi-account-plan.md` | Not built | Matrix | #102 |
| Delete account | `settings.dart:283` | — | Built: `Settings/DeleteAccount.swift`, `DevicesProxy.deactivateAccount` (ADR 0034) | Twake (common settings) else Matrix | #170 |

## Chat list

| Feature | Flutter | Web | iOS | Server | Issue |
|---|---|---|---|---|---|
| Rooms by activity, unread, invitations accept and decline | `chat_list`, `invitation_selection` | Phase 2, 3 | Built: `ChatList/ChatListScreen.swift`, `ChatListViewModel.swift` | Matrix | — |
| Filters, favourites, low priority, swipe and multiple selection | `chat_list/room_list_filter`, `slidable_chat_list_item` | Phase 2b, 11 | Built: `ChatListScreen.swift` | Matrix | — |
| Draft on the row, mark all read, offline banner, quick switcher | `chat_draft` | Phase 2b, 11 | Built: `ChatListViewModel.swift`, `MarkAllRead.swift`, `Connectivity.swift`, `QuickSwitcher.swift` | Matrix | — |
| Preview a chat on long press | — | — | Built: `ChatList/ChatPreview.swift` (#154); Open in its menu; a tap on the preview does not open the chat (SwiftUI, ADR 0036) | Matrix | #132 |
| Typing on the row, presence dot, room kind badge, space unread | `chat_list_item_subtitle` | D182 | Built: `ChatList/ChatListScreen.swift` (`ChatListRow`), `RowPresence.swift`, `RowSpaceUnread.swift`, `Domain/Models/SpaceUnread.swift`; presence read when the row shows ([ADR 0031](../../docs/adr/0031-chat-list-row-marks.md)) | Matrix (presence: `GET /presence`, off on some servers) | #105, #136, #144, #145 |
| Archive (web account data `app.twake.chat.archived_rooms`) | `archive` | D176 | Built: `ChatList/ArchivedChats.swift`, `Domain/Models/RoomArchive.swift` | Matrix | — |
| Public groups: browse, join, knock | `public_rooms` | D206 | Built: `ChatList/PublicRooms.swift`, `MatrixData/Proxies/PublicRoomsProxy.swift` | Matrix | — |
| Spaces: browse, join, mark read, new channel, `page_style` | `space_home` | Phase 3 | Built: `ChatList/Spaces.swift`, `PageStyleViews.swift`, `SpacesProxy.swift` | Matrix | — |
| Create a space and a sub-space | route `newspace` | Phase 3 | Built: `ChatList/NewSpace.swift`, `Domain/Models/NewSpace.swift`, `SpacesProxy.createSpace` ([ADR 0036](../../docs/adr/0036-spaces-and-folders-in-the-chat-list.md)) | Matrix | #177 |
| Folders | `settings_folders`, `domain/spaces/folders.dart` | D237, D318 | Built: `ChatList/Folders.swift`, `FolderScreens.swift`, `Domain/Models/Folder.swift`, `FoldersProxy` (ADR 0036); built-in folders keep the iOS chips | Matrix (account data) | #176 |
| Activity: mentions, inbox, reactions to own messages | — | Phase 6, D57, D318 | Built: `ChatList/Activity.swift`, `ActivityReactionsProxy.swift` (#159) | Matrix | — |
| Activity and push for followed threads | — | Phase 6 | Not built | Matrix | #93 |
| Saved messages | — | Phase 11 | Built: `ChatList/SavedMessages.swift`, `Domain/Models/SavedMessages.swift` | Matrix | — |
| Global search: chats, people, server messages | `search` | D147, D199, D228, D238 | Built: `ChatListViewModel.searchMessages`; encrypted rooms through the on-device index (`MatrixData/Search/MessageIndex.swift`, ADR 0040), messages the app has decrypted only | Matrix + ToM | #94 |
| Do not disturb with a banner | — | Phase 11 | Built: `SettingsScreen.swift`, `Connectivity.swift` (`.m.rule.master`) | Matrix | — |
| App grid of Twake apps | `app_grid` | — | Built: `Settings/AppGrid.swift`, `TwakeChat/TwakeApps.json` (ADR 0034) | Twake (build setting) | #174 |
| Broadcast lists (one message into each direct chat) | — | MSG-29, not built on the web | Not built | Matrix | none: no reference |

## Chat screen

| Feature | Flutter | Web | iOS | Server | Issue |
|---|---|---|---|---|---|
| Send, reply, edit, delete, retry, reactions, recent reactions | `chat` | Phase 2, 2b | Built: `Room/ComposerView.swift`, `MessageActions.swift`, `MessageRow.swift` | Matrix | — |
| Formatted messages, mentions, spoilers shown, Markdown sending | `chat/events` | Phase 2, 2b | Built: `Room/MessageBody.swift`, `Domain` `MatrixHTML` | Matrix | — |
| Formatting toolbar | — | Phase 2 | Built: `Room/TextFormatting.swift` (#134) | Matrix | — |
| Spoiler in the toolbar | — | MSG-23 | Built: `TextFormatting.swift`, `MatrixData/Mappers/RichMarkdown.swift`, [ADR 0035](../../docs/adr/0035-timeline-extras-formats.md) | Matrix | #178 |
| Emoji shortcodes, bot commands (MSC4332) | `command_hints` | README | Built: `Room/EmojiSuggestions.swift`, `Domain/Models/BotCommand.swift` | Matrix | — |
| Custom emotes and packs (MSC2545) | `settings_emotes` | — | Built: shown, picked and sent (`RoomViewModel+Emotes.swift`); packs not editable, [ADR 0035](../../docs/adr/0035-timeline-extras-formats.md) | Matrix | #186 |
| Stickers: shown / sent | `sticker_picker_dialog` | — | Built: `StickerViews.swift` (shown without a bubble), sent from MSC2545 packs, [ADR 0028](../../docs/adr/0028-gifs-stickers-checklists.md) | Matrix | #105 |
| GIF picker | — | D63, D146 | Built: `GifPickerSheet.swift`; received GIFs not hidden when off, no owner switch yet | Twake (common proxy), ADR 0028 | #140 |
| Typing line, receipts, Seen by, unread marker, mark unread | `seen_by_row` | Phase 2, 2b | Built: `Room/RoomScreen.swift`, `TimelineRows.swift` | Matrix | — |
| Draft per chat and per thread, reopen where left | `chat_draft` | Phase 2b | Built: `TimelineRepository.saveDraft`, `Room/TimelineScrollMemory.swift` | Matrix | — |
| Forward, pin, edit history (encrypted too), report, ignore | `forward`, `chat_pinned_events` | Phase 2b | Built: `Room/PinnedAndForward.swift`, `MatrixData/Proxies/EncryptedEditHistory.swift` | Matrix | — |
| Select many messages, select part of a text, go to a date | `chat` selection | Phase 2b | Built: `Room/MessageSelection.swift`, `SelectTextSheet.swift`, `HistoryLoading.swift` | Matrix | — |
| Search in a chat: unencrypted on the server, encrypted on device | `chat_search` | Phase 4 (D21) | Built: `Room/RoomSearch.swift`, `RoomSearchProxy.swift`, on-device index of decrypted messages (ADR 0040) | Matrix | #94 |
| Threads: list, reply, thread screen | — | Phase 2 | Built: `Room/Threads.swift`, `ThreadPrefsProxy.swift` | Matrix | #93 (notifications) |
| Polls (MSC3381) | — | Phase 10 | Built: `Room/Polls.swift`, `Domain/Models/Poll.swift` | Matrix | — |
| Checklists next to polls | — | THR-11 | Off: no event format defined ([ADR 0028](../../docs/adr/0028-gifs-stickers-checklists.md)) | Matrix | #105 |
| Voice messages (MSC3245), playback speed | `chat_audio_player_widget` | Phase 10 | Built: `Room/VoiceRecorder.swift`, `Players.swift`. Same event as web (`adapters/matrix/matrixAttachments.ts`) and Flutter (`pages/chat/chat.dart:914`): `m.audio` with `org.matrix.msc3245.voice` and `org.matrix.msc1767.audio` (`duration` in ms, `waveform` integers 0 to 1024); the received waveform and duration are drawn (`TimelineMessage.Voice`) | Matrix | #108 |
| Transcribe a voice message | — | MSG-13 | Built: on-device `SFSpeechRecognizer` (`SpeechTranscriber.swift`) | Device | #182 |
| Translate a message | — | MSG-15 | Built: Apple Translation on the device (`MessageTranslationViews.swift`) | Device (ADR 0026) | #181 |
| Scribe in the composer | — | D53, D73, D215 | Not built; owner decision | Twake (Assistant) | #183 |
| Scheduled send | — | CMP-03, web #1185 | Built: MSC4140 called directly, hidden in encrypted rooms ([ADR 0035](../../docs/adr/0035-timeline-extras-formats.md)) | Matrix (MSC4140, detected) | #184 |
| Link preview, none in encrypted rooms | `domain/preview_url` | Phase 11, D211 | Built: `MatrixData/Proxies/LinkPreviewProxy.swift` | Matrix | — |
| Author removes a link preview | — | CMP-09 | Off: the web has no format ([ADR 0035](../../docs/adr/0035-timeline-extras-formats.md)) | Matrix | #185 |
| Tombstone and blocked user banners, device verification banner | `tombstone_display`, `blocked_user_banner`, `chat_device_verifycation_banner` | — | Built: `Room/RoomBanners.swift` | Matrix | — |
| Status on the author's avatar | — | NOT-04 | Built: `RoomViewModel+Presence.swift` (dot on the timeline avatar) | Matrix | #180 |
| Hardware keyboard: Return sends, Up edits | `chat_input_row_web` | Phase 2b | Built: `ComposerKeys.swift` | Device | #142 |
| Broadcast channels (`app.twake.chat.page`) | `newfeed` (`app.twake.chat.feed`) | Phase 3, D2, D90 | Built: `Domain/Models/Broadcast.swift`; web form kept (ADR 0023) | Matrix | — |
| Twake Assistant in rooms | — | D74, D102, D128, D212 | Not built; owner decision | Twake (Assistant) | #190 |
| Public web page of a channel | — | D112, D178 | Off: not built until the owner asks (ADR 0026, ADR 0036) | Twake (side service) | #189 |

## Media and files

| Feature | Flutter | Web | iOS | Server | Issue |
|---|---|---|---|---|---|
| Inline pictures and video, viewer, Quick Look, save to Photos | `image_viewer`, `media_viewer` | Phase 2, 11 | Built: `Room/MediaViews.swift`, `SaveToPhotos.swift` | Matrix | — |
| Preview before sending, album, camera, paste, drag and drop | `send_media_native_dialog`, `domain/media_album` | Phase 2 | Built: `Room/AttachmentPicking.swift`, `AttachmentDrop.swift`. Albums are read by `app.twake.chat.batch` (`MatrixData/Mappers/MediaBatch.swift`), the key Flutter writes on each picture of a send of two or more (`domain/media_album/policy/media_batch_stamp.dart`); iOS does not write it yet, so its multi-picture sends show as single pictures on Flutter and web | Matrix | #210 |
| Upload progress, size limit from `/media/v3/config` | `send_file_dialog` | Phase 2 | Built: `MatrixData/Proxies/MediaProxy.swift` | Matrix | — |
| Media, Files, Links tabs in chat info | `chat_details_page_view` | — | Built: `Room/RoomDetailsScreen.swift` | Matrix | — |
| Alternative text on sent pictures | — | A11Y-04 | Built: sent as the picture's caption ([ADR 0035](../../docs/adr/0035-timeline-extras-formats.md)) | Matrix | #179 |
| Twake Drive picker | `drive_picker` (unmerged) | D36, D200 | Not built; "+" › Files | Twake (Drive) | #175 |
| Location: shown | — | — | Built: `Domain/Models/GeoPoint.swift`, `MessageBody.swift` | Matrix | — |

## People and rooms

| Feature | Flutter | Web | iOS | Server | Issue |
|---|---|---|---|---|---|
| New direct chat, new group, invite members | `new_private_chat`, `new_group` | Phase 3 | Built: `People/PeopleScreens.swift`, `PeopleProxy.swift` | Matrix | — |
| Contacts through the ToM directory | `contacts_tab`, `domain/contact` | Phase 3, D79 | Built: `MatrixData/Discovery/TwakeContactLookup.swift` | ToM | — |
| ToM address book: add, edit | `add_contact_dialog`, `tom_address_book_source` | — | Built: `TomContactsProxy.swift`, `TomContactsAPI.swift`, `TwakeContactsViewModel.swift`, `TwakeContactsViews.swift` (list, add, rename, remove; ADR 0037) | ToM | #187 |
| Invite by e-mail (3pid) and phone contacts | `contacts_invitation`, `phonebook_contact_repository` | `InviteDialog.tsx` | Built: `IdentityServerProxy.swift`, `PhoneContactsViewModel.swift`, `ThirdPartyInviteViews.swift` (search rows, third-party invites, phone contacts after permission and terms) | Matrix (identity server, ADR 0029) | #95 |
| Invitation link and status through ToM | `contacts_invitation_view_model`, `invitation_api` | — | Built: phone contacts invited through ToM, shared invitation link, Invitations page with status (`TwakeContactsViews.swift`; ADR 0037) | ToM | #188 |
| Chat details, members, roles, remove, ban, access, encryption | `chat_details`, `assign_roles`, `room_access` | Phase 3 | Built: `Room/RoomDetailsScreen.swift`, `MemberProfile.swift` | Matrix | — |
| Person card, groups in common, status message | `profile_info`, `chat_profile_info` | Phase 3, 10, 11 | Built: `Room/MemberProfile.swift` | Matrix | #111 (polling) |
| Matrix links open in the app | `invitation_link_web` (dropped) | Phase 5 | Built: `Domain/Models/MatrixLink.swift`, `TwakeChat/LinkRouter.swift` | Matrix | — |
| Personal QR | `personal_qr` | — | Built: `Settings/PersonalQR.swift` (the `matrix.to` link as a QR code, Share, Copy link) and `Settings/QRCodeScanner.swift` (scan into `MatrixLink`, which also reads Flutter's `links.twake.app/chat/…`); download to Photos is the share sheet's Save Image | Matrix (ADR 0030) | #105 |
| Support chat and Help | `create_support_chat_interactor`, `settings.dart:275` | — | Built: `Settings/HelpAndSupport.swift` (ADR 0034) | Twake (well-known, build setting) | #171 |

## Encryption and security

| Feature | Flutter | Web | iOS | Server | Issue |
|---|---|---|---|---|---|
| Recovery key, emoji verification, identity reset | `bootstrap`, `key_verification` | Phase 4 | Built: `Settings/DevicesAndVerification.swift`, `VerificationProxy.swift` | Matrix | #79, #116 |
| Recovery key kept by ToM | `data/network/recovery_words` | D14 | Built: `MatrixData/Proxies/TomRecoveryVault.swift` (ADR 0024) | ToM | #87, #120 |
| QR verification | `key_verification` | D28 | Off: no SDK release up to 26.11.23 exposes it in `SessionVerificationController`; emoji only | Matrix (ADR 0030) | #104 |
| Devices: list, rename, sign out | `device_settings` | Phase 4 | Built: `DevicesAndVerification.swift`, `DevicesProxy.swift` | Matrix | — |
| Identity changed warning | — | Phase 4 | Built: `Room/RoomBanners.swift` | Matrix | — |
| App lock | `widgets/lock_screen.dart` | — | Built: `TwakeChat/AppLock.swift` | Device | #114 |

## Notifications

| Feature | Flutter | Web | iOS | Server | Issue |
|---|---|---|---|---|---|
| Push through the Twake gateway, decrypted in the NSE | push | Phase 6 | Built: `MatrixData/Proxies/PusherProxy.swift`, `TwakeChatNSE/` | Twake (gateway, build setting) | #86, #88 |
| Inline reply, communication notifications | push | — | Not built | Matrix | #91 |
| Levels per room, account defaults, keywords | `settings_notifications` | Phase 6, D22, D85 | Built: `Settings/SettingsScreen.swift`, `AccountSettingsProxy.swift` | Matrix | — |
| Share suggestions | — | — | Built: `TwakeChat/ShareSuggestions.swift` (#168) | Device | — |

## Calls

| Feature | Flutter | Web | iOS | Server | Issue |
|---|---|---|---|---|---|
| Meet link button and call events in the timeline | `chat_video_call_button`, `domain/video_call` | D30, D105 | Built: `Room/MeetCalls.swift`, `MatrixData/Discovery/TwakeMeet.swift`, `Mappers/CallEvents.swift` (#161) | ToM + Twake (Meet) | — |
| Calls in the app (MatrixRTC, LiveKit, ringing) | `dialer` | Phase 7, 7 bis | Built ([ADR 0038](../../docs/adr/0038-in-app-calls-with-element-call-widget.md)): Element Call in a web view driven by the SDK widget driver (`MatrixData/Proxies/ElementCallProxy.swift`, `Room/RoomCalls.swift`), start or join from the header, active-call banner, CallKit (`Room/CallKitReporter.swift`); shown only with a `livekit_service_url` focus. Incoming ring in the background not built | Matrix + LiveKit token service | #191 |

## Settings

| Feature | Flutter | Web | iOS | Server | Issue |
|---|---|---|---|---|---|
| Profile name and picture | `settings_profile` | Phase 3 | Built: `Settings/EditProfileSheet.swift` | Matrix | — |
| Chat display: hide room events | `settings_chat` | — | Built: `TwakeChat/ChatDisplayDefaults.swift` | Device | — |
| Blocked users | `settings_blocked_users` | Phase 2b | Built: `SettingsScreen.swift` (ignored users) | Matrix | — |
| Data and storage, linked e-mails and phones | `settings_data_and_storage`, `settings_3pid` | D78 | Built: add and remove an e-mail (link) or a phone (SMS code) with user-interactive auth, `SettingsScreen.swift`, `AccountSettingsProxy.swift` | Matrix | #98 |
| Contacts visibility | `settings_contacts_visibility` | D78 | Built: `TwakeContactLookup.swift` | ToM | #98 |
| App language, translations | `settings_app_language`, `assets/l10n` | D67 | Common settings language applied (`TwakeChat/CommonSettingsLanguage.swift`, #172); translations not built | Device; ToM for D67 | #90 |
| Analytics with consent | — | D24, D26, D404 | Built, off in both builds: `Domain/Models/Analytics.swift`, `MatrixData/Proxies/AnalyticsProxy.swift`, `Settings/UsageAnalytics.swift` (ADR 0034) | Twake (side service) | #173 |
| Stories, emotes settings, style (theme, wallpaper) | `settings_stories`, `story`, `settings_style` | — | Dropped (ADR 0026): not in Twake's settings list, iOS system appearance | — | none |
| iPad layout | `chat_adaptive_scaffold` | Phase 8 | Built: `DesignSystem/Layout/TwakeLayout.swift`, `TwakeChat/ChatShell.swift` | Device | #103 |
| Localisation, accessibility pass, performance | `assets/l10n` | Phase 8, 9 | Partly | Device | #90, #96 |

## Reference-client facts (#115)

Checked on 2026-11-26: Flutter `twake-on-matrix` at `9c769f877`, web `twake-space-chat` at `67f2ca6e`.

| Fact | Finding | Evidence |
|---|---|---|
| Flutter: edit history UI | None: an edited message shows "edited" next to its time; edits are aggregated only to resend failed ones | `lib/pages/chat/events/message_time.dart:63`, `lib/pages/chat/chat.dart:1220` |
| Web: sending stickers | Not sent and not drawn: `m.sticker` is an unsupported type; the GIF decision says "no stickers" | `src/adapters/matrix/readMessages.ts:72`, `DECISION.md` (GIF entry, "Limits") |
| Flutter: accessibility | Minimal: four `Semantics` widgets and a few `semanticLabel`s, no accessibility pass | `lib/pages/chat/events/images_builder/image_bubble.dart`, `lib/pages/chat_list/room_list_filter/` |
| Flutter: crash reporting | Sentry (`sentry_flutter` 9.10), DSN from `AppConfig.sentryDsn`, off in local builds | `pubspec.yaml:173`, `lib/utils/sentry_init.dart`, `lib/main.dart:149` |
| Flutter: album format | `app.twake.chat.batch`, a UUID on each picture of a send of two or more | `lib/domain/media_album/policy/media_batch_stamp.dart:21` |

## Cross-cutting

| Item | iOS | Issue |
|---|---|---|
| One read of the server's features (ADR 0026) | Built: `Domain/Models/ServerCapabilities.swift`, `MatrixData/Proxies/ServerCapabilitiesProxy.swift` (ADR 0034) | #192 |
| Share extension | Built: `TwakeChatShare/` | — |
| First-launch cleanup over the Flutter app | Owner decision | #10, #87 |
