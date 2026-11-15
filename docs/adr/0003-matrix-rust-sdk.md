---
type: ADR
title: "ADR 0003: Use the Matrix Rust SDK through its Swift package"
description: "The app is built on matrix-rust-sdk's Swift bindings, which requires sliding sync on the homeserver."
tags: [adr, matrix, sdk]
status: draft
---
# ADR 0003: Use the Matrix Rust SDK through its Swift package

**Status:** Accepted by the project owner, 2026-11-11.

## Context
A native app needs a Matrix SDK for sync, storage and end-to-end encryption. Two exist for iOS: the older
Objective-C/Swift SDK, which is in maintenance, and the Rust SDK with generated Swift bindings
(`matrix-rust-components-swift`), which is actively developed. The Flutter app's own Notification Service Extension
already uses the Rust SDK package. The Rust SDK syncs with sliding sync; `matrix.linagora.com` advertises
`org.matrix.simplified_msc3575` (checked 2026-11-11).

## Decision
- The app uses the Matrix Rust SDK through its Swift package, added with Swift Package Manager.
- The package is pinned to an exact version. An upgrade is its own pull request.
- Only `Packages/MatrixData` imports it ([ADR 0006](0006-sdk-behind-proxy-protocols.md)).
- The app requires a homeserver with sliding sync and tells the user clearly when a server lacks it.

## Consequences
**Good.** Maintained crypto and sync; the same SDK in the app and in the extension; fast start through sliding sync.
**Costly.** The Swift API changes between releases, so upgrades need work. The binary is large. Homeservers without
sliding sync cannot be used. **Alternatives rejected.** The older iOS SDK: in maintenance, no future. Writing a client
on the raw HTTP API: encryption alone makes this unreasonable.

## When to revisit
If a Twake deployment that must be supported cannot enable sliding sync, or if the Swift bindings stop being published.
