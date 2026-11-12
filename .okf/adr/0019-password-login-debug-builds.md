---
type: ADR
title: "ADR 0019: Offer password login in Debug builds only"
description: "Debug builds sign in with m.login.password against the staging homeserver behind #if DEBUG; Release stays SSO-only as ADR 0008 says."
tags: [adr, authentication, security]
status: draft
---
# ADR 0019: Offer password login in Debug builds only

**Status:** Accepted by the project owner, 2026-11-12 (TWAK-62). Partly amends [ADR 0008](0008-authentication-sso-and-discovery.md) for Debug builds only.

## Context
[ADR 0008](0008-authentication-sso-and-discovery.md) says the app signs in with SSO and that password login is not
offered in v1. SSO is not built yet, and the first usable build needs a way to sign in so the migrated chat code can be
run against a real homeserver. The priority is migrating the code, not designing a new sign-in.

Checked 2026-11-12 on the staging homeserver `https://matrix.stg.lin-saas.com`:
- `/_matrix/client/v3/login` lists `m.login.password`.
- `/_matrix/client/versions` lists `org.matrix.simplified_msc3575: true`, so staging has sliding sync, which
  [ADR 0003](0003-matrix-rust-sdk.md) requires.

The pinned SDK has the password login call and the server's login flows; see
[Matrix SDK 26.04.01 API](../references/matrix-sdk-26-04-01-api.md) (Login, session, restore and logout).

## Decision
- Debug builds offer `m.login.password` through the SDK's
  `Client.login(username:password:initialDeviceName:deviceId:)`.
- The password sign-in code is gated with `#if DEBUG` in the app target's composition root, so a Release build does
  not contain it.
- Release builds stay SSO-only as [ADR 0008](0008-authentication-sso-and-discovery.md) says. In this round Release
  builds have no sign-in screen and are not distributed. This is the owner's decision for this round; it is stricter
  than the release rule of [ADR 0012](0012-reuse-flutter-bundle-identifier.md), which allows internal and TestFlight
  builds.
- The default development homeserver is `https://matrix.stg.lin-saas.com`. It lives in the Debug build configuration
  and is not a secret. No user name or password is committed.
- The session is saved as [ADR 0007](0007-shared-session-store-app-group.md) says.

## Consequences
**Good.** The migrated code can be signed in and run before SSO exists, with the smallest amount of new code; Release
behaviour does not change. **Costly.** The app handles a password in Debug builds; a Release build cannot sign in, so
nothing can go to TestFlight until SSO lands. Review must check that the password code stays behind `#if DEBUG`.
**Alternatives rejected.** Build SSO first: delays running any migrated code. Password login in every build: contradicts
ADR 0008 and is not how Twake accounts sign in.

## When to revisit
When SSO lands, or when a build must go to TestFlight or internal testers.
