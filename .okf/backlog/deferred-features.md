---
type: Task
title: "Deferred Features"
description: "Flutter features left out of v1, to be ordered after v1 is tested."
tags: [roadmap, scope]
status: draft
---
# Deferred Features

**State:** open - order not decided ([ADR 0011](../adr/0011-v1-scope-core-chat.md)).

Taken from the Flutter app's `lib/pages` and `lib/domain`. The list may be incomplete.

| Feature | Flutter location | Note |
|---|---|---|
| Contacts and new private chat | `contacts_tab`, `new_private_chat`, `domain/contact` | Needs the ToM server |
| New group, invitations | `new_group`, `invitation_selection` | |
| Search (rooms and in-room) | `search`, `chat_search` | |
| Spaces | `space_home`, `domain/spaces` | |
| Calls | `dialer`, `domain/video_call` | Needs VoIP push |
| Forward and share extension | `forward`, `share` | A third target; existing users lose it on update until it is rebuilt ([ADR 0012](../adr/0012-reuse-flutter-bundle-identifier.md)) |
| Drive picker | `drive_picker`, `domain/drive` | |
| Multiple accounts | `multiple_accounts` | Affects the session store layout |
| Chat details, profile, roles | `chat_details`, `chat_profile_info`, `profile_info` | |
| Public rooms | `public_rooms` | |
| Stories, archive, app grid, personal QR | `story`, `archive`, `app_grid`, `personal_qr` | |
| iPad layout | `chat_adaptive_scaffold` | v1 is iPhone only |
| Localisation beyond the first language | `lib/generated`, `assets/l10n` | Which languages ship in v1 is not decided |
