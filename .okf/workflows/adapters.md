---
type: Reference
title: "Agent Adapters"
description: "Every coding agent is pointed at .okf/index.md; no agent gets its own copy of the knowledge."
tags: [agents, okf]
status: draft
---
# Agent Adapters

The knowledge lives only in `.okf/`. Each coding agent gets one short instruction file that says: read
`.okf/index.md` first, keep the rules in [Constraints](../engineering/constraints.md), and run the checks in
[Build](build.md) and [Test](test.md) before finishing.

| File | For |
|---|---|
| `CLAUDE.md` | Claude Code |
| `AGENTS.md` | Codex and other agents that read it |
| `README.md` | People, and agent runners configured to read it first |

These files hold no facts of their own, so there is one place to update.
