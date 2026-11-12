---
type: ADR
title: "ADR 0001: Record architecture decisions"
description: "Decisions that are expensive to reverse are written as numbered ADRs in this folder."
tags: [adr, process]
status: draft
---
# ADR 0001: Record architecture decisions

**Status:** Accepted by the project owner, 2026-11-11.

## Context
The app starts from an empty repository and will be built partly by coding agents. The Flutter Twake Chat app already
records decisions as ADRs. Without a record, each contributor or agent re-derives or silently changes the architecture.

## Decision
Every decision that is expensive to reverse, or that a reasonable engineer would make differently, is one file in
`.okf/adr/`, numbered in order, using the [ADR Template](_template-adr.md). An accepted ADR is superseded by a new one,
not edited. The project owner accepts or rejects each ADR; an agent may only propose.

## Consequences
**Good.** One place explains why the code is the way it is; reviews can cite a number. **Costly.** A small writing cost
per decision. **Alternatives rejected.** Decisions in pull request descriptions only: not findable later.

## When to revisit
If ADRs stop being read or kept current.
