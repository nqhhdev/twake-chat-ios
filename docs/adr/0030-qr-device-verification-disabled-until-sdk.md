---
type: ADR
title: "ADR 0030: Verify devices with emoji only until the SDK exposes QR verification"
description: "Proposed: QR device verification stays off because no matrix-rust-components-swift release exposes it; emoji verification stays the only method, and the missing FFI API is a candidate upstream contribution. The personal QR code and the QR scanner are built without the SDK."
tags: [adr, matrix, sdk, encryption, verification, qr]
status: draft
---
# ADR 0030: Verify devices with emoji only until the SDK exposes QR verification

**Status:** Proposed, 2026-11-25 (#104, parity epic #112).

## Context
The Flutter app (Matrix Dart SDK) and the web client (`twake-space-chat/src/ds/CameraScanner/readQrCode.ts`) verify
a new device by showing a QR code on one device and scanning it with the other (`m.qr_code.show.v1`,
`m.qr_code.scan.v1`, `m.reciprocate.v1`). Issue #104 asks for the same on iOS.

The iOS app reaches encryption only through `matrix-rust-components-swift` ([ADR 0003](0003-matrix-rust-sdk.md),
[ADR 0006](0006-sdk-behind-proxy-protocols.md)), pinned at 26.04.01 ([ADR 0015](0015-pin-matrix-rust-components-swift-26-04-01.md)).
What was checked on 2026-11-25:

| Where | QR device verification |
|---|---|
| 26.04.01 bindings (`Sources/MatrixRustSDK/matrix_sdk_ffi.swift`, tag `26.04.01`, matrix-rust-sdk `388ced09`) | No. `SessionVerificationController` has `requestDeviceVerification`, `requestUserVerification`, `acknowledgeVerificationRequest`, `acceptVerificationRequest`, `startSasVerification`, `approveVerification`, `declineVerification`, `cancelVerification`; `SessionVerificationData` is `emojis` or `decimals`. The only QR types (`QrCodeData`, `QrCodeIntent`, the login and grant-login handlers) are for signing in a new device (MSC4108), not for verifying one. |
| 26.11.23, the newest release (matrix-rust-sdk `f4a94ad6`) | No. The same controller plus `requestCancelInfo` and `sasCancelInfo`; `SessionVerificationData` unchanged. |
| matrix-rust-sdk `main`, `bindings/matrix-sdk-ffi/src/session_verification.rs` | No. Only SAS. `bindings/matrix-sdk-ffi/Cargo.toml` does not turn on the `matrix-sdk` feature `qrcode`. |
| matrix-rust-sdk `main`, `crates/matrix-sdk` | Yes, in Rust only: `VerificationRequest::generate_qr_code`, `VerificationRequest::scan_qr_code` and `QrVerification` (`reciprocate`, `confirm`), behind the `qrcode` feature. |

No release between 26.04.01 and 26.11.23 adds it, so an SDK bump does not unlock the feature.

## Decision
- QR device verification is **off**. The app shows no QR option in device verification, and no code for it is
  written until the bindings expose it ([ADR 0011](0011-v1-scope-core-chat.md): no code for a deferred feature).
- Emoji verification (SAS) stays the only method, in both directions, as `DevicesAndVerification.swift` does it
  today. A Flutter or web device that offers QR and SAS falls back to emoji with this app.
- No SDK bump is made for this: no release would help, and a bump is its own pull request (ADR 0003, ADR 0015).
- The personal QR code (#105) and the QR scanner do not need the SDK: the QR code holds the user's `matrix.to` link
  and the scanner hands what it reads to the existing `MatrixLink` routing. They are built in the Settings feature
  (`PersonalQR.swift`, `QRCodeScanner.swift`). When QR verification arrives, it reuses this scanner.
- The personal QR code holds `https://matrix.to/#/<user id>`, which every Matrix client opens. The Flutter app's
  QR code holds `https://links.twake.app/chat/<user id>?fallback=https://sign-up.twake.app` instead; the scanner
  reads both, so a Flutter user's code opens here too.

### Upstream contribution
The missing piece is small and sits in matrix-rust-sdk, not in this app. A pull request to
`bindings/matrix-sdk-ffi` would:
1. turn on the `qrcode` feature of `matrix-sdk` in `bindings/matrix-sdk-ffi/Cargo.toml`;
2. add to `SessionVerificationController`: `start_qr_verification() -> Vec<u8>` (calls
   `VerificationRequest::generate_qr_code` and returns `QrVerification::to_bytes` to draw), `scan_qr_code(data: Vec<u8>)`
   (parses `QrVerificationData::from_bytes` and calls `VerificationRequest::scan_qr_code`, which sends
   `m.reciprocate.v1`), and `confirm_qr_scanned()` for the device that showed the code (`QrVerification::confirm`);
3. add `SessionVerificationData::QrCode { data: Vec<u8> }` and delegate callbacks for "the other device scanned my
   code" and "the scan was reciprocated", following the existing `did_start_sas_verification`;
4. advertise `m.qr_code.show.v1`, `m.qr_code.scan.v1` and `m.reciprocate.v1` in the request methods when the feature
   is on, with tests in `bindings/matrix-sdk-ffi` and an entry in its changelog.
Once it ships in a `matrix-rust-components-swift` release, this app bumps the pin in its own pull request and adds
show and scan next to emoji verification.

## Consequences
**Good.** No unsupported crypto code in the app: verification uses only what the SDK exposes. Emoji verification
already works with Flutter, web and Element. The scanner and QR drawing are ready for when the SDK catches up.
**Costly.** Users who are used to scanning on Flutter or web compare emoji instead, which takes longer. #104 stays
open until the SDK exposes the API.
**Alternatives rejected.** Building QR verification in the app from the to-device events: it would duplicate the
crypto state machine the SDK owns and break ADR 0006. Bumping to 26.11.23: it does not add the API. Depending on
`matrix-sdk-crypto-ffi` (the older bindings that do expose QR): a second crypto store beside the main SDK's.

## When to revisit
When a `matrix-rust-components-swift` release exposes QR verification in `SessionVerificationController` (search
the bindings for `qr` next to `startSasVerification`), or when the owner decides to send the upstream pull request.
