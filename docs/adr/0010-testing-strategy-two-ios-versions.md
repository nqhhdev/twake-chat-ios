---
type: ADR
title: "ADR 0010: Test logic with fakes and UI on both iOS versions"
description: "View models and use cases are unit-tested against fake proxies; shared components are checked on iOS 18 and iOS 26 simulators."
tags: [adr, testing, ios-26]
status: draft
---
# ADR 0010: Test logic with fakes and UI on both iOS versions

**Status:** Accepted by the project owner, 2026-11-11.
**Amended by [ADR 0020](0020-opt-in-local-staging-integration-tests.md), 2026-11-12.**

## Context
The project rule is that every change in behaviour comes with a test. The SDK cannot be driven in unit tests without a
server, and the app looks different on its two iOS versions.

## Decision
- Unit tests use Swift Testing and live in each package's test target.
- View models and use cases are tested against hand-written fakes of the Domain protocols. No mocking library.
- Mappers in `MatrixData` are tested with fixture values; proxies themselves are thin and are covered by integration tests.
- `DesignSystem` components have snapshot tests recorded and compared on one iOS 18 simulator and one iOS 26 simulator.
- CI runs the unit tests once and the snapshot tests on both simulators.
- Integration tests against a real homeserver are out of scope until a test server exists.

## Consequences
**Good.** Fast, deterministic tests for logic; the two-version requirement is checked by a machine. **Costly.** Two
sets of reference images; a snapshot tool must be chosen (not decided). **Alternatives rejected.** UI tests as the main
safety net: slow and flaky. Testing against the real SDK in unit tests: needs a server.

## When to revisit
When a test homeserver is available, or when snapshot upkeep costs more than it catches.
