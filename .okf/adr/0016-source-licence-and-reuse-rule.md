---
type: ADR
title: "ADR 0016: Choose the licence and the reuse rule for code from other clients"
description: "Either relicense to AGPL-3.0 and port with attribution, or stay MIT and reimplement clean-room, reusing only the Apache-2.0 Element X snapshot."
tags: [adr, licence, migration]
status: draft
---
# ADR 0016: Choose the licence and the reuse rule for code from other clients

**Status:** Proposal approved by the project owner on 2026-11-11 (card TWAK-2, answer "Approved"). The owner has
**not yet chosen** option 1 or option 2 below, and has not confirmed the copyright holder. Until they do, no code is
copied, translated or ported from any source in the table below.

## Context
`twake-chat-ios` is MIT, "Copyright (c) 2026 Huy Quang Nguyen" (`LICENSE`). The migration reads these sources:

| Source | Licence found | Evidence |
|---|---|---|
| twake-on-matrix, Flutter app (`lib/`) | AGPL-3.0 | `LICENSE:1`; FluffyChat/Famedly AGPL headers in `lib/utils/background_push.dart:3` and `lib/utils/matrix_sdk_extensions/hive_collections_database.dart:5`; other Dart files have no header and fall under the repo licence |
| twake-on-matrix, NSE Swift (`ios/NSE/`) | Apache-2.0, New Vector Ltd, for 59 of 64 files | Copied from Element X iOS in commit `42746d711` ("TW-1049 Copy element-x files", 2023-11-30), e.g. `ios/NSE/HTMLParsing/ElementXAttributeScope.swift:2`. The other 5 are SwiftGen output, `DesignKit/Package.swift` and `DesignKitTests.swift`. 10 later commits touched `ios/NSE`; those edits are Linagora's and fall under the repo's AGPL-3.0 |
| element-ios (legacy Riot app) | AGPL-3.0 or Element commercial | `LICENSE`, `LICENSE-COMMERCIAL`, headers `SPDX-License-Identifier: AGPL-3.0-only` |
| matrix-rust-sdk ([ADR 0003](0003-matrix-rust-sdk.md)) | Apache-2.0 | Compatible with either option |

AGPL code cannot be copied or translated into an MIT repository. Element X upstream has since moved to AGPL, so only
the Apache-headed snapshot of 2023-11-30 is reusable under MIT.

## Decision
The owner picks one:

1. **Relicense to AGPL-3.0.** Code from all three sources may be ported with attribution and its original headers.
   `LICENSE` is replaced with AGPL-3.0 and the copyright line chosen below.
2. **Keep MIT with a clean-room rule.** No line is copied or translated from twake-on-matrix `lib/`, from Linagora's
   post-2023-11-30 edits to `ios/NSE`, from element-ios, or from current Element X. Behaviour is reimplemented from the
   running Flutter app, the Matrix specification and the Rust SDK documentation; "what moves" in the migration inventory
   means "what is reimplemented". The Apache-2.0 files as they were at `42746d711` may be reused with their headers kept
   and a `NOTICE` file added when the first one is reused. `LICENSE` changes only in its copyright line, if at all.

Either way, the owner confirms the copyright holder: the current line names a person, while the app replaces Linagora's
Twake Chat Flutter app and reuses its bundle identifier ([ADR 0012](0012-reuse-flutter-bundle-identifier.md)).

## Consequences
**Option 1. Good.** Fast ports, consistent with twake-on-matrix and Linagora's other Twake clients. **Costly.** Network
copyleft for every user of the code; the MIT grant already given by the existing commits is superseded.
**Option 2. Good.** Permissive licence kept. **Costly.** Every slice is rewritten, not moved; reviewers must check
provenance; an automatic guard only catches files that kept their header.

## Enforcement
None on this branch yet. Card TWAK-2 built a `swift test` guard (`Tools/LicenceGuard`) that fails when a `.swift`, `.m`,
`.h` or `.dart` file carries an AGPL or Element-commercial marker. It is not merged. It fits option 2 and is removed
under option 1.

## When to revisit
When the owner picks an option; if Linagora's legal team sets a licence policy for Twake clients; or if code from a new
source is needed.
