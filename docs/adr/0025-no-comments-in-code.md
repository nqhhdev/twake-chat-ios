---
type: ADR
title: "ADR 0025: No comments in Swift code"
description: "Proposed: Swift files hold no comments at all, doc comments included; the reason behind the code lives in an ADR or the knowledge base, and scripts/check-no-comments.sh fails on any comment."
tags: [adr, conventions, code-style, review]
status: draft
---
# ADR 0025: No comments in Swift code

**Status:** Proposed, 2026-11-24, from the project owner's rule of that day ("No comments in code, ban 100%; if
needed, write an ADR to replace comments in code"). It takes effect when the existing comments are removed; see
Rollout.

## Context
- On `main` (`e02b846`), 276 of 321 Swift files hold 2,782 comment lines: about 2,530 `///` doc comments, 250 `//`
  comments, 3 block comments and 9 `// MARK:` lines.
- Many of them repeat what the code already says. Others hold reasons: a Matrix spec rule, the Flutter or web
  client behaviour being matched, a limit of the pinned SDK ([ADR 0015](0015-pin-matrix-rust-components-swift-26-04-01.md)).
  Those reasons are spread across files, are not reviewed as decisions, and go stale without anyone noticing.
- This repository already keeps its reasons in [ADRs](index.md) and in the [knowledge base](../../.okf/index.md).
- swift-format ([ADR 0014](0014-ci-github-actions-swift-format.md)) has no rule that bans comments.
  `AllPublicDeclarationsHaveDocumentation` is off in `.swift-format`, so removing doc comments breaks no lint rule.

## Decision
- **No comment in a Swift file.** No `//`, `///`, `/* */` or `/** */` outside a string or regex literal, in app,
  package, extension and test code alike. `// MARK:` is a comment too.
- **One exception.** The first line of a `Package.swift`, `// swift-tools-version:...`, which SwiftPM requires.
- **Where the reason goes instead.**
  - A decision that is expensive to reverse, or that a reasonable engineer would make differently: an ADR.
  - Behaviour matched from another client, a protocol detail or a limit of the SDK: the knowledge base page that owns
    the area (`.okf/`), which can name the file or type.
  - What the code does: names, small types and tests whose names state the behaviour.
  - Why a change was made: the commit message and the pull request.
- **Enforced by** `scripts/check-no-comments.sh` (rule 6 in the [Constraints](../../.okf/engineering/constraints.md)), run by
  CI's architecture job, with its own tests in `scripts/tests/check_no_comments_test.sh`.
- **Out of scope.** Shell, YAML and Python files keep their `#` comments. The trees under
  `scripts/tests/architecture-fixtures/` are test data for the architecture check, which must prove it ignores
  comments, so the check skips them.

## Rollout
1. This ADR, the constraint, the check and its tests, without CI running the check yet, so open pull requests are
   not broken.
2. After the open pull requests (#151 to #162) merge: the comments are removed, one pull request per package
   (Domain, AppShared, DesignSystem, MatrixData, Features, app and extensions). The removal changes no code.
   Before each pull request, the comments that hold a reason not already written down are listed for the owner,
   who picks which become an ADR or a knowledge base note.
3. The last of those pull requests turns the check on in CI.

## Consequences
**Good.** One place for reasons, reviewed like any decision. Nothing to go stale beside the code. Smaller diffs and
files. The rule is checked by a script, not by review.

**Costly.** Xcode Quick Help and DocC show no documentation for any type. A reader must open the knowledge base or
an ADR to learn why code is written a certain way, and nothing in the file points there. Code taken from Apple
templates or other projects must be stripped first. Removing about 2,800 lines touches almost every file once.

**Alternatives rejected.**
- *Keep `///` doc comments, ban `//`.* Most comments here are doc comments, so the problem would stay. The owner
  asked for a full ban.
- *Allow a "why" comment when it is short.* Needs judgment in every review and leads back to today's state.
- *Leave it to review.* A rule nobody enforces is a wish ([Constraints](../../.okf/engineering/constraints.md)).

## When to revisit
If the app ships a public Swift library that needs DocC, or if reasons kept out of the code are found to be lost or
ignored in review.
