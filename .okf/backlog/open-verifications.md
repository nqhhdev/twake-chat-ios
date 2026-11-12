---
type: Task
title: "Open Verifications"
description: "Assumptions in this knowledge base that nobody has confirmed yet."
tags: [verification]
status: draft
---
# Open Verifications

**State:** open.

| Assumption | Used in | How to confirm |
|---|---|---|
| Every deployment to support has sliding sync | [ADR 0003](../adr/0003-matrix-rust-sdk.md) | Ask the server team; check `/_matrix/client/versions` on each. The 26.04.01 client has the setting (`ClientBuilder.slidingSyncVersionBuilder`, TWAK-48); that says nothing about the servers. Confirmed on staging `matrix.stg.lin-saas.com` 2026-11-12 (`org.matrix.simplified_msc3575: true`, [ADR 0019](../adr/0019-password-login-debug-builds.md)); other deployments are still unconfirmed |
| The SDK supports the SSO login-token flow as described, and cross-process store locking | [ADR 0008](../adr/0008-authentication-sso-and-discovery.md), [ADR 0007](../adr/0007-shared-session-store-app-group.md) | Found in the 26.04.01 API, not yet run (TWAK-48): `Client.startSsoLogin` returns an `SsoHandler` with `url()` and `finish(callbackUrl:)`; `ClientBuilder.crossProcessLockConfig` takes `CrossProcessLockConfig.multiProcess(holderName:)`. See [Matrix SDK 26.04.01 API](../references/matrix-sdk-26-04-01-api.md). Still to confirm: sign in by SSO against a Twake server, and share one store between the app and the extension |
| The exact iOS 26 glass APIs in the Design System sketch | [Design System](../architecture/components/design-system.md) | Build against the iOS 26 SDK |
| The push gateway's existing registration works unchanged for the native app | [ADR 0009](../adr/0009-push-gateway-and-nse-decryption.md) | Register a pusher from a test build and send a message |
| Where the Flutter app leaves its files and Keychain items, matching the drop list of ADR 0017 | [ADR 0012](../adr/0012-reuse-flutter-bundle-identifier.md), [ADR 0017](../adr/0017-flutter-upgrade-keep-and-drop-lists.md) | Install the Flutter app, sign in, then inspect the containers and Keychain |
| How the Flutter app's own device and pusher are removed: the shared Keychain holds only the dedicated notification device, the app's token is in the SQLite database | [ADR 0017](../adr/0017-flutter-upgrade-keep-and-drop-lists.md) open point 1, [ADR 0012](../adr/0012-reuse-flutter-bundle-identifier.md) | Owner rules on open point 1 (logout via SQLite token, superseding ADR 0012, or leave the device and filter pushes) |
| How updating users recover encryption: v1 either calls `GET /_twake/recoveryWords` once at recovery, or users type a key they may never have seen. Deleting the Flutter recovery-key items is already decided by ADR 0012 | [ADR 0017](../adr/0017-flutter-upgrade-keep-and-drop-lists.md) open point 2, [ADR 0007](../adr/0007-shared-session-store-app-group.md), [ADR 0011](../adr/0011-v1-scope-core-chat.md) | Owner rules on open point 2; check how many users have seen their recovery key |
| The native app is signed by team `KUT463DS29`, which the Keychain group and App Group require | [ADR 0017](../adr/0017-flutter-upgrade-keep-and-drop-lists.md) open point 3 | Check the signing team in App Store Connect with the owner |
| The new SDK store directory is `Library/Application Support/TwakeChat/SDK` in the App Group container | [ADR 0017](../adr/0017-flutter-upgrade-keep-and-drop-lists.md) open point 4, [ADR 0007](../adr/0007-shared-session-store-app-group.md) | Owner confirms the name. `AppGroupContainer` in AppShared fixes it as the one SDK store directory until then (TWAK-63); another answer changes only that constant |
| Service name of the Flutter app's default secure-storage items (`hive_encryption_key`, `chat.twake.app_lock`, `ssss_recovery_key_<userId>`) | [ADR 0017](../adr/0017-flutter-upgrade-keep-and-drop-lists.md) | Install the Flutter app, sign in, list the Keychain items |
| ADR 0013 baseline waits for the owner: whether behaviour is ported from twake-on-matrix `5a3e9e849` on `origin/main`. No rule rests on it until then | [ADR 0013](../adr/0013-flutter-baseline-and-feature-status.md), [ADR 0018](../adr/0018-behaviour-oracle-for-v1.md) | Owner accepts ADR 0013 or names another commit |
| Which licence option applies (AGPL-3.0 port, or MIT clean-room) and who holds the copyright | [ADR 0016](../adr/0016-source-licence-and-reuse-rule.md) | Owner picks option 1 or 2 and confirms the copyright line |
| What happens to twake-on-matrix: do Android, web and desktop stay there, and is it (and its iOS build) frozen, maintained in parallel or retired | Card TWAK-1 question 3 | Owner answers; no proposal was made |
| SwiftUI can scroll a long timeline smoothly | [ADR 0004](../adr/0004-swiftui-observable-coordinators.md) | A throwaway prototype |
| Snapshot tool, crash reporting (the linter and CI service are decided in [ADR 0014](../adr/0014-ci-github-actions-swift-format.md)) | [Build](../workflows/build.md), [Test](../workflows/test.md) | Decide and record as ADRs |
