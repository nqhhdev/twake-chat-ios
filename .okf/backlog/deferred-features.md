---
type: Task
title: "Deferred Features"
description: "Replaced by the Parity Matrix: ADR 0011's deferred list is no longer kept here."
tags: [roadmap, scope]
status: draft
---
# Deferred Features

**State:** replaced, 2026-11-25. [ADR 0011](../../docs/adr/0011-v1-scope-core-chat.md) (Accepted) deferred every
Flutter feature beyond core chat; the code has built most of them since 2026-11-13, and
[ADR 0026](../../docs/adr/0026-matrix-first-client-server-features.md) (Proposed) makes full parity with
`twake-on-matrix` and `twake-space-chat` the scope, with every non-Matrix server feature detected, never assumed.

The feature list, each feature's state in the code with file evidence, the server it needs and the issue that
tracks it are kept in one place: the [Parity Matrix](parity-matrix.md). This page stays so that older links resolve;
do not add rows here.
