---
type: ADR
title: "ADR 0005: Layers as local Swift packages"
description: "Features, Domain, MatrixData, DesignSystem and AppShared are separate local packages so import rules are compile errors."
tags: [adr, architecture, modules]
status: draft
---
# ADR 0005: Layers as local Swift packages

**Status:** Accepted by the project owner, 2026-11-11.

## Context
The Flutter app keeps `pages`, `domain` and `data` as folders of one package, so nothing stops a page from importing a
data class. The native app also has a second process, the Notification Service Extension, that must reuse the data code
without pulling in screens.

## Decision
Code lives in local Swift packages under `Packages/`, with these allowed imports:

| Package | May import |
|---|---|
| `Domain` | Foundation |
| `DesignSystem` | SwiftUI |
| `AppShared` | Foundation, Security, OSLog |
| `MatrixData` | `Domain`, `AppShared`, the Matrix SDK |
| `Features/<Feature>` | `Domain`, `DesignSystem` |
| App target | everything |
| Notification Service Extension | `MatrixData`, `Domain`, `AppShared` |

A feature does not import another feature; flows that cross features are joined by a coordinator in the app target.

## Consequences
**Good.** A wrong import does not compile; features build and test alone; the extension links only what it needs.
**Costly.** More `Package.swift` files and `public` declarations. **Alternatives rejected.** One target with folders:
rules rely on review only. One package per screen: too fine for a v1 of five features.

## When to revisit
If build times or package overhead outweigh the benefit, or when a second app (macOS, share extension) needs a different cut.
