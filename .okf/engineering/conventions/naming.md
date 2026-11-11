---
type: Convention
title: "Naming and Placement"
description: "Where each kind of file lives and what it is called - one table, one row per kind."
tags: [naming, structure]
status: draft
---
# Naming and Placement

Planned; adjust when the first feature is written. Swift API Design Guidelines apply to everything not listed.

| Kind | Lives in | Named | Example |
|---|---|---|---|
| Screen view | `Packages/Features/<Feature>/Sources/<Feature>/<Screen>/` | `<Screen>Screen` | `ChatListScreen` |
| View model | next to its screen | `<Screen>ViewModel` | `ChatListViewModel` |
| Coordinator | `Packages/Features/<Feature>/Sources/<Feature>/` | `<Flow>Coordinator` | `AuthenticationCoordinator` |
| Domain model | `Packages/Domain/Sources/Domain/Models/` | noun, no suffix | `RoomSummary`, `TimelineItem` |
| Repository protocol | `Packages/Domain/Sources/Domain/Repositories/` | `<Thing>Repository` | `RoomListRepository` |
| Use case | `Packages/Domain/Sources/Domain/UseCases/` | `<Verb><Noun>UseCase` | `SignOutUseCase` |
| Domain error | next to the protocol that throws it | `<Area>Error` | `AuthenticationError` |
| Proxy | `Packages/MatrixData/Sources/MatrixData/Proxies/` | `<Thing>Proxy` | `TimelineProxy` |
| Mapper | `Packages/MatrixData/Sources/MatrixData/Mappers/` | `<DomainType>Mapper` | `TimelineItemMapper` |
| Shared component | `Packages/DesignSystem/Sources/DesignSystem/Components/` | noun | `AvatarView`, `MessageBubble` |
| Version-adaptive modifier | `Packages/DesignSystem/Sources/DesignSystem/Adaptive/` | `adaptive<What>` | `adaptiveSurface` |
| Test fake | the package's test support target | `Fake<Protocol>` | `FakeRoomListRepository` |
| Test file | `Tests/<Module>Tests/` | `<TypeUnderTest>Tests` | `ChatListViewModelTests` |

One primary type per file; the file is named after it.
