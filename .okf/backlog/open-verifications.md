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
| Every deployment to support has sliding sync | [ADR 0003](../adr/0003-matrix-rust-sdk.md) | Ask the server team; check `/_matrix/client/versions` on each. The 26.04.01 client has the setting (`ClientBuilder.slidingSyncVersionBuilder`, TWAK-48); that says nothing about the servers |
| The SDK supports the SSO login-token flow as described, and cross-process store locking | [ADR 0008](../adr/0008-authentication-sso-and-discovery.md), [ADR 0007](../adr/0007-shared-session-store-app-group.md) | Found in the 26.04.01 API, not yet run (TWAK-48): `Client.startSsoLogin` returns an `SsoHandler` with `url()` and `finish(callbackUrl:)`; `ClientBuilder.crossProcessLockConfig` takes `CrossProcessLockConfig.multiProcess(holderName:)`. See [Matrix SDK 26.04.01 API](../references/matrix-sdk-26-04-01-api.md). Still to confirm: sign in by SSO against a Twake server, and share one store between the app and the extension |
| The exact iOS 26 glass APIs in the Design System sketch | [Design System](../architecture/components/design-system.md) | Build against the iOS 26 SDK |
| The push gateway's existing registration works unchanged for the native app | [ADR 0009](../adr/0009-push-gateway-and-nse-decryption.md) | Register a pusher from a test build and send a message |
| Where the Flutter app leaves its files and Keychain items, and that the old session can be signed out with them | [ADR 0012](../adr/0012-reuse-flutter-bundle-identifier.md) | Install the Flutter app, sign in, then inspect the containers and Keychain |
| SwiftUI can scroll a long timeline smoothly | [ADR 0004](../adr/0004-swiftui-observable-coordinators.md) | A throwaway prototype |
| Snapshot tool, crash reporting (the linter and CI service are decided in [ADR 0014](../adr/0014-ci-github-actions-swift-format.md)) | [Build](../workflows/build.md), [Test](../workflows/test.md) | Decide and record as ADRs |
