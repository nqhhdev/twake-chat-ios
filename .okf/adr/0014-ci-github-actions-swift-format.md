---
type: ADR
title: "ADR 0014: CI on GitHub Actions with GitHub-hosted macOS runners; swift-format for formatting and lint"
description: "CI runs on GitHub Actions macOS runners like the Flutter app, and swift-format from Xcode formats and lints; billed macOS minutes are the price."
tags: [adr, ci, build, lint]
status: draft
---
# ADR 0014: CI on GitHub Actions with GitHub-hosted macOS runners; swift-format for formatting and lint

**Status:** Accepted by the project owner, 2026-11-12 (TWAK-37). The answer date is not recorded anywhere, so this is the date it was written down.

## Context
The repository has no CI and no linter. [Build](../workflows/build.md) lists "Format and lint" as not chosen, and
[Open Verifications](../backlog/open-verifications.md) lists the CI service and the linter as undecided. Several
constraints already assume a CI build ([Constraints](../engineering/constraints.md), rows 5, 8 and 9). The Flutter
app's CI runs on GitHub Actions with GitHub-hosted macOS runners (`twake-on-matrix/.github/workflows`). swift-format
ships with Xcode 26, so it needs no extra dependency. The app must be built and tested on an iOS 18 and an iOS 26
simulator ([ADR 0010](0010-testing-strategy-two-ios-versions.md)).

## Decision
- CI runs on GitHub Actions, on GitHub-hosted macOS runners.
- swift-format, the version that ships with the Xcode used by CI, is the only formatter and linter.

## Consequences
**Good.** The same CI service as the Flutter app, so no new account or setup. No extra tool to install or pin for
formatting and lint.
**Costly.** macOS minutes are billed on a private repository. The iOS 18 simulator runtime may not be preinstalled on
the runner image and may have to be downloaded on each run, which costs time and minutes. swift-format has fewer rules
than SwiftLint.
**Alternatives rejected.** SwiftLint: one more dependency to install and pin, for rules the project does not need yet.
Self-hosted runners or another CI service: a machine or account to maintain, and different from the Flutter app.

## When to revisit
If CI cost or simulator runtime downloads become a problem, or if a lint rule the project needs exists only in another tool.
