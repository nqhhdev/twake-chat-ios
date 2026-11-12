---
type: Component
title: "Domain Layer"
description: "C4 level 3 - app models, repository protocols and use cases, free of SwiftUI and of the Matrix SDK."
tags: [c4, component, domain]
status: draft
---
# Domain Layer

| | |
|---|---|
| Folder | `Packages/Domain/` |
| Holds | Value-type models (`RoomSummary`, `TimelineItem`, `UserSession`), repository protocols, use cases, typed errors |
| May import | Foundation only |
| Must not import | SwiftUI, UIKit, the Matrix SDK, any other package of this repository |

## Files
- `Sources/Domain/Models/UserSession.swift`: `UserSession`, the signed-in session (user id, device id, homeserver URL,
  access token, optional refresh token). Its `description` and `debugDescription` leave the tokens out (TWAK-63).
- `Sources/Domain/Repositories/AuthenticationRepository.swift`: password login, restoring the saved session and logout,
  each `async throws(AuthenticationError)`. Password login is for Debug builds ([ADR 0019](../../adr/0019-password-login-debug-builds.md)).
- `Sources/Domain/Repositories/AuthenticationError.swift`: `invalidCredentials`, `serverUnreachable`,
  `invalidHomeserverURL`, `unknown`. No case carries a token or server text.

## Rules
- Models are `struct` or `enum`, `Sendable`, and carry no SDK type. Anything from the SDK is mapped in [Data](data.md).
- A repository protocol describes what a feature needs, for example `RoomListRepository` exposing an `AsyncSequence` of
  room summaries. It does not mirror the SDK's API.
- A use case exists only when logic spans more than one repository or is reused by more than one view model. A view
  model may call a repository protocol directly otherwise. The Flutter app has an interactor for every call; this app
  deliberately does not.
- Expected failures are typed errors (`AuthenticationError`, `TimelineError`), thrown from `async throws` functions.
