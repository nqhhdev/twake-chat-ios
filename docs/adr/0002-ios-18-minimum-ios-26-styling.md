---
type: ADR
title: "ADR 0002: Minimum iOS 18, iOS 26 styling isolated in the Design System"
description: "The app deploys to iOS 18 and adopts iOS 26 Liquid Glass only inside the DesignSystem package."
tags: [adr, ios, ui, ios-26]
status: draft
---
# ADR 0002: Minimum iOS 18, iOS 26 styling isolated in the Design System

**Status:** Accepted by the project owner, 2026-11-11.

## Context
The app must run on two iOS versions: iOS 18 and iOS 26. iOS 26 changes the system look (Liquid Glass) and adds APIs
that do not exist on iOS 18. The Flutter app's deployment target is iOS 16. Availability checks scattered through
feature code are hard to test and hard to remove later.

## Decision
- The deployment target is iOS 18.0. The app is built with the iOS 26 SDK.
- Any code that differs between the two versions lives in `Packages/DesignSystem`, behind a modifier or component.
- Feature packages contain no `#available` and no `@available` for iOS versions.
- Each shared component is checked on both an iOS 18 and an iOS 26 simulator
  ([ADR 0010](0010-testing-strategy-two-ios-versions.md)).

## Consequences
**Good.** Modern SwiftUI and the Observation framework everywhere without fallbacks; one package to edit when iOS 18 is
dropped. **Costly.** Users on iOS 16 and 17, whom the Flutter app still serves, cannot install this app. Some iOS 26
behaviour arrives automatically with the new SDK and still needs a visual check on both versions.
**Alternatives rejected.** iOS 17 or 16 minimum: more fallback code, and on 16 no Observation framework. iOS 26 only:
too few devices.

## When to revisit
When iOS 18 usage among Twake users is low enough to drop it, or if a needed non-visual API exists only on iOS 26.
