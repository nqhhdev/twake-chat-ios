---
type: ADR
title: "ADR 0004: SwiftUI with Observable view models and coordinators"
description: "Screens are SwiftUI views driven by one @Observable view model each; coordinators own navigation."
tags: [adr, ui, swiftui, state]
status: draft
---
# ADR 0004: SwiftUI with Observable view models and coordinators

**Status:** Accepted by the project owner, 2026-11-11.

## Context
With iOS 18 as the minimum, SwiftUI, the Observation framework and Swift concurrency are all available without
fallbacks. The Flutter app separates pages, state and routing (`go_router`); the native app needs the same separation
with native tools and as few third-party libraries as possible.

## Decision
- UI is SwiftUI. A UIKit view is allowed only wrapped inside a `DesignSystem` component, with the reason written next to
  it (the message composer is the likely case).
- Each screen has one view model: `@MainActor @Observable final class`, dependencies passed to its initializer.
- Navigation belongs to coordinators that own a `NavigationStack` path and sheet state. Views do not push other views.
- Asynchronous work uses `async`/`await` and `AsyncSequence`. New code does not use Combine.
- The project builds in Swift 6 language mode with strict concurrency checking.
- No third-party state-management or dependency-injection library. Dependencies are built in the app target's
  composition root and passed down.

## Consequences
**Good.** Little framework to learn; view models are plain classes that are easy to test. **Costly.** Coordinators are
hand-written. A very long timeline may need tuning or a UIKit list later. **Alternatives rejected.** The Composable
Architecture: powerful but a large dependency and learning cost. UIKit screens: no need at this deployment target.
`ObservableObject` with Combine: superseded by Observation.

## When to revisit
If timeline scrolling cannot be made smooth in SwiftUI, or if view models grow enough shared logic to justify a library.
