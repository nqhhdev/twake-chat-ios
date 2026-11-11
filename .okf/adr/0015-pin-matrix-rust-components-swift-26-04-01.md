---
type: ADR
title: "ADR 0015: Pin matrix-rust-components-swift at exactly 26.04.01"
description: "The SDK package is pinned to 26.04.01, the version the Flutter app's extension uses; it is older than Element X, so API names come from the pinned package."
tags: [adr, matrix, sdk]
status: draft
---
# ADR 0015: Pin matrix-rust-components-swift at exactly 26.04.01

**Status:** Accepted by the project owner, 2026-11-12 (TWAK-38). The answer date is not recorded anywhere, so this is the date it was written down.

## Context
[ADR 0003](0003-matrix-rust-sdk.md) says the app uses `matrix-rust-components-swift` pinned to an exact version, but
names no version. The Flutter app's Notification Service Extension pins the same package with `kind = exactVersion`,
`version = 26.04.01` (`twake-on-matrix/ios/Runner.xcodeproj/project.pbxproj:1968-1974`). Element X iOS, the main
reference for using the package, follows newer releases.

## Decision
- `matrix-rust-components-swift` is pinned at exactly `26.04.01` (Swift Package Manager `exactVersion`).
- This ADR fills in the version ADR 0003 leaves open. It does not supersede ADR 0003, whose rules all still apply: an
  upgrade is its own pull request, and only `Packages/MatrixData` imports the package.

## Consequences
**Good.** The same SDK version as the Flutter app's extension, already used against Twake servers.
**Costly.** The pin is older than current Element X. SDK API names and signatures must be read from the pinned
package, not from Element X `main`, whose code may call APIs this version lacks or names differently. Whether this
version supports the SSO login-token flow and cross-process store locking is still unconfirmed, and stays open in
[Open Verifications](../backlog/open-verifications.md).
**Alternatives rejected.** The latest release: newer APIs and Element X code that matches, but untried against Twake
servers and different from the extension's version. Leaving the version open: ADR 0003 requires an exact pin.

## When to revisit
When a needed fix or API exists only in a later release; the upgrade is then its own pull request (ADR 0003).
