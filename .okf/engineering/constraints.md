---
type: Constraint
title: "Constraints"
description: "Every rule the code must keep, what enforces it, and the page that owns the reasoning - re-check before you finish."
tags: [rules, review]
status: draft
---
# Constraints

A rule nobody enforces is a wish: the tool is named, or "review" is written honestly. To change a rule, write or
supersede an [ADR](../adr/index.md) first. The package dependency rule and the Swift 6, strict concurrency and
no-warnings rule are enforced today by the `Package.swift` files and the build settings, and the CI job `ci`
(`.github/workflows/ci.yml`, [Build](../workflows/build.md#ci)) builds and tests every pull request. Every other
"Enforced by" below is still the plan until the code it checks exists. `scripts/check-architecture.sh` runs first in
`scripts/test.sh` and fails, naming the rule and its ADR, on any break of the rules it lists.

| Rule | Enforced by | Owner |
|---|---|---|
| Packages import only what [ADR 0005](../adr/0005-layered-local-swift-packages.md) allows | The compiler: package dependencies in each `Package.swift`; `scripts/check-architecture.sh` rules 3 (allowed local package dependencies, no feature on a feature) and 4 (system imports in `Domain`, `AppShared` and `DesignSystem` sources) | [Components](../architecture/components/index.md) |
| Only `MatrixData` imports the Matrix SDK; no SDK type in a public Domain or feature API | The compiler (only `MatrixData` declares the dependency); `scripts/check-architecture.sh` rule 1 (no SDK import or package declaration outside `MatrixData`) | [ADR 0006](../adr/0006-sdk-behind-proxy-protocols.md) |
| No `#available` / `@available` iOS version checks outside `DesignSystem` | `scripts/check-architecture.sh` rule 2 (text search of every Swift file outside `Packages/DesignSystem`) | [ADR 0002](../adr/0002-ios-18-minimum-ios-26-styling.md) |
| View models are `@MainActor @Observable`; views hold no logic | Review | [ADR 0004](../adr/0004-swiftui-observable-coordinators.md) |
| Swift 6 language mode, strict concurrency, no warnings | Build settings; CI job `ci` (iOS 26 test build and iOS 18.0 deployment-target build) | [Build](../workflows/build.md) |
| Secrets only in the Keychain; the recovery key is never stored | Review | [ADR 0007](../adr/0007-shared-session-store-app-group.md) |
| Push payloads and logs never contain message content | Review | [ADR 0009](../adr/0009-push-gateway-and-nse-decryption.md) |
| Every change in behaviour comes with a test | Review; CI job `ci` runs the tests | [Test](../workflows/test.md) |
| Shared components pass snapshot tests on iOS 18 and iOS 26 | CI | [ADR 0010](../adr/0010-testing-strategy-two-ios-versions.md) |
| The Matrix SDK is pinned to an exact version; upgrades are their own pull request | `Package.resolved`, review; `scripts/check-architecture.sh` rule 5 (a `Package.swift` that declares the SDK uses `exact:`) | [ADR 0003](../adr/0003-matrix-rust-sdk.md) |
| Password login only in Debug builds | `#if DEBUG` in the app target's composition root; review | [ADR 0019](../adr/0019-password-login-debug-builds.md) |
| No secrets in source or committed configuration | Review; a secret scanner is not chosen | Not written yet |
| No public App Store release until the project owner accepts the feature gap; TestFlight and internal builds only | Review, release process | [ADR 0012](../adr/0012-reuse-flutter-bundle-identifier.md) |
| The Flutter app's leftover session, files and Keychain items are removed on first launch | A test, once the code exists | [ADR 0012](../adr/0012-reuse-flutter-bundle-identifier.md) |
| No code for a deferred feature in v1 | Review | [ADR 0011](../adr/0011-v1-scope-core-chat.md) |
