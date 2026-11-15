---
type: Component
title: "Design System"
description: "C4 level 3 - colours, typography and shared components; the only place that branches on the iOS version."
tags: [c4, component, ui, ios-26]
status: draft
---
# Design System

| | |
|---|---|
| Folder | `Packages/DesignSystem/` (planned) |
| Holds | Colour and typography tokens, shared components (avatar, message bubble, buttons), version-adaptive modifiers |
| May import | SwiftUI only |
| Must not import | [Domain](domain.md), [Data](data.md), any feature |

## Two iOS versions, one place
The app runs on iOS 18 and iOS 26. iOS 26 introduces the Liquid Glass material; iOS 18 does not have it. Every
difference is hidden behind a modifier or component here, for example:

```swift
public extension View {
    /// Glass on iOS 26, the system material on iOS 18.
    @ViewBuilder func adaptiveSurface(in shape: some Shape) -> some View {
        if #available(iOS 26, *) {
            glassEffect(.regular, in: shape)
        } else {
            background(.regularMaterial, in: shape)
        }
    }
}
```

The sketch shows the intent; check the exact iOS 26 API against the SDK in use before copying it.

Feature code calls `adaptiveSurface` and never writes `#available`. When iOS 18 support ends, only this package changes.
Reasoning: [ADR 0002](../../../docs/adr/0002-ios-18-minimum-ios-26-styling.md).

## Source of the visual language
The Flutter app's colours, typography and component shapes are the reference. Whether tokens are copied by hand or
generated from a shared source is not decided.
