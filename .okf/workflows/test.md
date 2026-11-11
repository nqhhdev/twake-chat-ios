---
type: Workflow
title: "Test"
description: "How unit and snapshot tests will be run, and on which iOS versions."
tags: [test, ci, ios-26]
status: draft
---
# Test

> Not runnable yet: no test target exists. Replace this page with the real commands when the first one is created.

## Planned
| Kind | Where | Runs on |
|---|---|---|
| Unit tests (Swift Testing) | Each package's test target | One simulator; once per CI run |
| Snapshot tests of `DesignSystem` | `DesignSystem` test target | One iOS 18 simulator and one iOS 26 simulator |
| Integration tests with a homeserver | None in v1 | - |

Rules and reasoning: [ADR 0010](../adr/0010-testing-strategy-two-ios-versions.md).

## Writing a test for a view model
1. Create fakes of the Domain protocols the view model needs.
2. Build the view model with them.
3. Call an action; assert on the view model's state.
