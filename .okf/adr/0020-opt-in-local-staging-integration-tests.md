---
type: ADR
title: "ADR 0020: Integration tests against staging are opt-in and local only"
description: "Integration tests read staging credentials at run time from a local env file or environment variables, skip when they are absent, and never run in CI."
tags: [adr, testing, security]
status: draft
---
# ADR 0020: Integration tests against staging are opt-in and local only

**Status:** Accepted by the project owner, 2026-11-12 (TWAK-62). Amends [ADR 0010](0010-testing-strategy-two-ios-versions.md).

## Context
[ADR 0010](0010-testing-strategy-two-ios-versions.md) says integration tests against a real homeserver are out of scope
until a test server exists. The staging homeserver `https://matrix.stg.lin-saas.com` is now the development
homeserver ([ADR 0019](0019-password-login-debug-builds.md)) and has test accounts. CI must not hold account
credentials, and the project has no secret scanner ([Constraints](../engineering/constraints.md)).

## Decision
- Integration tests against staging are opt-in and run locally only. CI never runs them.
- A test reads its credentials at run time from `~/.factos/secrets/twake-chat-ios-staging.env` or from the
  environment variables of the same names: `MATRIX_HOMESERVER`, `MATRIX_USER`, `MATRIX_PASSWORD`.
- When the credentials are absent, the test skips; it does not fail.
- Credential values are never committed: not in source, test fixtures, build configuration or this knowledge base.

## Consequences
**Good.** The proxies in `MatrixData` can be checked against a real server without putting a secret in the repository
or in CI. **Costly.** These tests prove nothing on a pull request; a developer must run them by hand, and a skipped run
looks like a pass. **Alternatives rejected.** Running them in CI with repository secrets: puts credentials in CI and
depends on staging being up for every pull request.

## When to revisit
When CI must check behaviour against a server, or when a dedicated test homeserver with throwaway accounts exists.
