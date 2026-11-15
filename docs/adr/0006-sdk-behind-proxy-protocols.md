---
type: ADR
title: "ADR 0006: The Matrix SDK is reached only through proxy protocols"
description: "MatrixData wraps each SDK object in a proxy that implements a Domain protocol; no SDK type leaves that package."
tags: [adr, matrix, sdk, testing]
status: draft
---
# ADR 0006: The Matrix SDK is reached only through proxy protocols

**Status:** Accepted by the project owner, 2026-11-11.

## Context
The SDK's Swift API is generated from Rust and changes between releases. Its objects are reference types with callback
listeners, which are awkward in SwiftUI and cannot be created in unit tests without a server.

## Decision
- `MatrixData` is the only package that imports the SDK.
- Each long-lived SDK object has one proxy (see [Data Layer](../../.okf/architecture/components/data.md)) that implements a
  protocol declared in `Domain`.
- Proxies map SDK types to Domain value types and SDK errors to Domain errors, and turn listeners into `AsyncStream`.
- View models and use cases depend on the protocols and are tested with hand-written fakes.

## Consequences
**Good.** An SDK upgrade touches one package; features are testable without a homeserver. **Costly.** A mapping layer
to write and maintain; a new SDK capability needs a protocol change before a feature can use it.
**Alternatives rejected.** Using SDK types directly in view models: fastest at first, then every upgrade touches every
feature and tests need a live server.

## When to revisit
If the mapping cost of the timeline proves too high for performance, a narrower exception for that one type can be recorded.
