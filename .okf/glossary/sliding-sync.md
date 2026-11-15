---
type: Term
title: "Sliding Sync"
description: "The Matrix sync method that loads only the rooms in view; required by the Matrix Rust SDK."
tags: [matrix]
status: draft
---
# Sliding Sync

The Matrix sync method that loads only the rooms in view instead of the whole account; required by the Matrix Rust SDK.
A homeserver shows support with `org.matrix.simplified_msc3575` in `/_matrix/client/versions`.
See [ADR 0003](../../docs/adr/0003-matrix-rust-sdk.md).
