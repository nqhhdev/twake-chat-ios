---
type: Task
title: "Deferred Features"
description: "Flutter features left out of v1, to be ordered after v1 is tested."
tags: [roadmap, scope]
status: draft
---
# Deferred Features

**State:** open - order not decided ([ADR 0011](../adr/0011-v1-scope-core-chat.md)).

Taken from the Flutter app's `lib/pages` and `lib/domain` at the baseline commit of
[ADR 0013](../adr/0013-flutter-baseline-and-feature-status.md). The list may be incomplete.

| Feature | Flutter location | Note |
|---|---|---|
| Contacts and new private chat | `contacts_tab`, `new_private_chat`, `domain/contact` | Needs the ToM server |
| New group, invitations | `new_group`, `invitation_selection` | |
| Web invitation link | `invitation_link_web` (route `/chat/:matrixid`) | Proposed for dropping (ADR 0013) |
| Search (rooms and in-room) | `search`, `chat_search` | |
| Spaces, folders | `space_home`, `domain/spaces`, `data/datasource_impl/folders` | |
| Calls | `dialer`, `domain/video_call` | Needs VoIP push |
| Forward and share extension | `forward`, `share` | Built 2026-11-13: forward in the message actions, the `TwakeChatShare` target ([Share Extension](../architecture/containers/share-extension.md)) |
| Drive picker | `drive_picker`, `domain/drive` | Only on the unmerged branch `feat/tom-3-drive-sso-foundation`, not in the baseline |
| Multiple accounts | `multiple_accounts` | Affects the session store layout |
| Chat details, profile, roles | `chat_details`, `chat_profile_info`, `profile_info` | |
| Public rooms | `public_rooms` | |
| Stories, archive, app grid, personal QR | `story`, `archive`, `app_grid`, `personal_qr` | |
| Drafts, pinned messages, album sending | `chat_draft`, `utils/room_draft_storage.dart`, `domain/media_album`, `domain/services/message_splitter.dart` | Whether v1 shows albums sent by other clients is open (ADR 0013) |
| Media viewer, download, URL preview | `image_viewer`, `media_viewer`, `domain/preview_url` | v1 shows images, video and files in the timeline only |
| Device settings | `device_settings` | v1 keeps signing this device out |
| Settings and app lock | `settings_dashboard`, `widgets/lock_screen.dart` | Language, chat, profile, contacts visibility, app lock |
| ToM recovery words | `data/network/recovery_words` | Needs the ToM server; v1 uses the recovery key |
| iPad layout | `chat_adaptive_scaffold` | v1 is iPhone only |
| Localisation beyond the first language | `lib/generated`, `assets/l10n` | Which languages ship in v1 is not decided |
