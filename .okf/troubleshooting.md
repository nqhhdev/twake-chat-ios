---
type: Reference
title: "Troubleshooting by Symptom"
description: "Common failure symptoms, each mapped to its likely cause and the page that explains it."
tags: [troubleshooting]
status: draft
---
# Troubleshooting by Symptom

No code exists yet. These rows are risks the design already knows about; replace them with real symptoms as they appear.

| Symptom | Likely cause | See |
|---|---|---|
| Notification says a message is encrypted instead of showing its text | The extension could not open the shared store or ran out of time | [ADR 0007](../docs/adr/0007-shared-session-store-app-group.md), [ADR 0009](../docs/adr/0009-push-gateway-and-nse-decryption.md) |
| Sign-in fails with "server not supported" | The homeserver has no sliding sync | [ADR 0003](../docs/adr/0003-matrix-rust-sdk.md) |
| A screen looks wrong on iOS 18 only | A version difference was written outside `DesignSystem` | [Design System](architecture/components/design-system.md) |
| After updating from the Flutter app, the user is asked to sign in and old messages are unreadable | Expected: a new device is created; the user must enter the recovery key | [ADR 0012](../docs/adr/0012-reuse-flutter-bundle-identifier.md) |
| Sign-in succeeds on the server (the crypto store is created) but `login` never returns | The SDK platform was not set up: `MatrixPlatform.setUp()` must run before any client is built | [Data Layer](architecture/components/data.md) |
| A feature package does not compile after importing the SDK | Only `MatrixData` may import it | [ADR 0006](../docs/adr/0006-sdk-behind-proxy-protocols.md) |
| Messages from Flutter or web senders stay unreadable on a new device ("Verify this device with your recovery key to read it.") | The sender withheld the key because this device was not cross-signed (`withheldForUnverifiedOrInsecureDevice`): twake-on-matrix shares keys only with verified devices. The unlock with the ToM key verifies the device; older keys then come from the backup if the sender uploaded them. Once verified, the help says the sender did not share the key | [ADR 0024](../docs/adr/0024-recovery-key-kept-by-tom.md) |
