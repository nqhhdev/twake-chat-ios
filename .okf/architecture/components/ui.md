---
type: Component
title: "Features Layer"
description: "C4 level 3 - SwiftUI screens, their view models and the coordinators that route between them."
tags: [c4, component, ui, swiftui]
status: draft
---
# Features Layer

| | |
|---|---|
| Folder | `Packages/Features/<Feature>/` (planned) |
| Holds | SwiftUI views, one `@Observable` view model per screen, a coordinator per flow |
| May import | [Domain](domain.md), [Design System](design-system.md) |
| Must not import | [Data](data.md), the Matrix SDK, another feature |

## Shape of a screen
- **View**: a SwiftUI `View` that renders the view model's state and forwards user actions. No logic beyond layout.
- **View model**: `@MainActor @Observable final class`. Receives repository protocols or use cases through its
  initializer, exposes plain state properties and `async` action methods.
- **Coordinator**: owns a `NavigationStack` path and sheet state for one flow, creates view models, and is the only place
  that knows which screen comes next.

A feature never checks the iOS version; that belongs to the [Design System](design-system.md).

Reasoning: [ADR 0004](../../adr/0004-swiftui-observable-coordinators.md).

## Planned features for v1
| Feature | Flutter counterpart (`lib/pages/`) |
|---|---|
| `Authentication` | `twake_welcome`, `homeserver_picker`, `connect`, `login` |
| `ChatList` | `chat_list` |
| `Room` | `chat` (timeline, composer, events) |
| `Encryption` | `bootstrap`, `key_verification`, `chat_encryption_settings` |
| `Settings` | `settings_dashboard` (sign-out and the minimum needed) |
