---
type: ADR
title: "ADR 0027: CI builds the app and runs the unit tests on every pull request"
description: "Proposed: two macOS jobs, build and unit tests, join format and architecture as required checks, so auto-merge never lands code that does not compile or fails a test; staging and E2E tests stay out."
tags: [adr, ci, build, test]
status: draft
---
# ADR 0027: CI builds the app and runs the unit tests on every pull request

**Status:** Proposed, 2026-11-25. Amends [ADR 0014](0014-ci-github-actions-swift-format.md) and the owner's
2026-11-13 decision that CI checks format only.

## Context
CI checked format and the architecture scripts only, on Ubuntu, because macOS minutes were billed at 10× and the
quota was tight. On 2026-11-25 the owner asked to "enable auto fix + auto merge + create PR after CI/CD pass" and
said "Pls auto and auto no need human review, I will review it after 100% func works well". The repository now has
auto-merge on, and `main` requires the format and architecture checks. Neither compiles Swift, so a pull request
could merge without ever being built or tested. The repository is public, so GitHub-hosted macOS runners cost
nothing. The `macos-26` image lists Xcode 26.0.1 to 26.6 and iOS 26.2, 26.4 and 26.5 simulators with an iPhone 17.
The staging integration tests skip without credentials ([ADR 0020](0020-opt-in-local-staging-integration-tests.md)),
and the E2E suite needs Docker, which `macos-26` cannot run.

## Decision
- `.github/workflows/ci.yml` gets two jobs on `macos-26`, on every pull request and every push to `main`:
  - `build`: `xcodebuild build` of the `TwakeChat` scheme for an iOS 26 simulator.
  - `unit tests`: `swift test` in `Packages/Domain` and `Packages/AppShared`, then `xcodebuild test` with the
    `TwakeChat` test plan on that simulator.
- Xcode and the simulator are pinned once in the workflow (`XCODE_VERSION`, `SIMULATOR_DESTINATION`), to a version
  the image lists. Both jobs share `.github/actions/xcode-setup`, which selects Xcode, restores the caches and
  resolves packages.
- A build error, a warning (the targets treat warnings as errors) or a failing test fails the job. The job names
  stay `build` and `unit tests`, because `main` requires them.
- The Swift package checkouts are cached, keyed on the `Package.resolved`, `Package.swift` and project files.
  DerivedData is cached per job, keyed on `Package.resolved`; only a green push to `main` saves it.
- Code must compile on both CI's Xcode (26.6) and the Xcode on the developers' Macs (27.2). A pull request that
  builds locally can still fail `build` or `unit tests`; CI's result is the one that counts.
- Staging integration tests run in the test plan and skip there, since CI holds no credentials (ADR 0020).
  `e2e.yml` stays manual and outside the gate.

## Consequences
**Good.** Nothing merges, by hand or by auto-merge, unless it compiles with no warning and passes every unit test.
Developers no longer have to remember to run the build before a pull request.
**Costly.** Each pull request waits for two macOS jobs, several minutes even with warm caches. CI's Xcode (26.6) is
older than the one on the developers' Macs (27.2), so code that uses a newer SDK or compiler feature fails CI until
the workflow moves to a newer image. If the repository becomes private, the macOS minutes are billed again.
**Alternatives rejected.** One job that builds and tests: one check for two different failures, and no parallelism.
`scripts/test.sh` as the CI step: it picks the simulator by name across all iOS 26 runtimes and does not take a
DerivedData path to cache. A self-hosted Mac: a machine to maintain. Running the E2E suite in the gate: it needs
Docker, which only the Intel image can run, and it takes much longer.

## When to revisit
If the repository becomes private, if the runner image drops the pinned Xcode, or if the app needs an SDK the image
does not have.
