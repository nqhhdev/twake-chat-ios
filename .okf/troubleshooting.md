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
| Notification says a message is encrypted instead of showing its text | The extension could not open the shared store or ran out of time | [ADR 0007](adr/0007-shared-session-store-app-group.md), [ADR 0009](adr/0009-push-gateway-and-nse-decryption.md) |
| Sign-in fails with "server not supported" | The homeserver has no sliding sync | [ADR 0003](adr/0003-matrix-rust-sdk.md) |
| A screen looks wrong on iOS 18 only | A version difference was written outside `DesignSystem` | [Design System](architecture/components/design-system.md) |
| After updating from the Flutter app, the user is asked to sign in and old messages are unreadable | Expected: a new device is created; the user must enter the recovery key | [ADR 0012](adr/0012-reuse-flutter-bundle-identifier.md) |
| A feature package does not compile after importing the SDK | Only `MatrixData` may import it | [ADR 0006](adr/0006-sdk-behind-proxy-protocols.md) |
