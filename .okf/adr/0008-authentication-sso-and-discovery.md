---
type: ADR
title: "ADR 0008: Sign in with SSO after server discovery"
description: "The app discovers the homeserver from its well-known document and signs in through the system web authentication session."
tags: [adr, authentication, sso, security]
status: draft
---
# ADR 0008: Sign in with SSO after server discovery

**Status:** Accepted by the project owner, 2026-11-11.
**Amended by [ADR 0021](0021-sign-in-as-the-flutter-app.md), 2026-11-13: the Flutter flow, with password sign-in for servers without SSO in every build. (ADR 0019, now superseded, had amended it for Debug builds.)**

## Context
Observed on `matrix.linagora.com` (2026-11-11): the homeserver offers `m.login.sso` with identity provider
`oidc-twake`, plus `m.login.token` and `m.login.password`; its discovery document names an OpenID issuer under
`m.authentication`. The Flutter app signs in with SSO: it opens the provider in a browser and receives a `loginToken`
on the redirect `twake.chat://login`, which it exchanges for a session.

## Decision
- The user enters or confirms a server; the app reads `/.well-known/matrix/client` and builds the SDK client from it.
- Sign-in uses SSO in `ASWebAuthenticationSession` with the callback `twake.chat://login`, the same as the Flutter app
  ([ADR 0012](0012-reuse-flutter-bundle-identifier.md)). The login token on the callback is exchanged through the SDK.
- Password login is not offered in v1, even where the server lists it.
- The session is saved as described in [ADR 0007](0007-shared-session-store-app-group.md).
- Sign-up is a link to the registration page from build configuration, opened in the same web session.

## Consequences
**Good.** The same account flow as the Flutter app; no password handled by the app. **Costly.** Servers that offer only
password login cannot be used in v1. **Alternatives rejected.** An embedded web view: can read credentials, and is
refused by many providers. Password form: not how Twake accounts sign in.

## Open points
- Whether the server will move to Matrix's OAuth 2.0 based authentication; the `m.authentication` entry suggests it is
  possible. The exact SDK calls for either flow must be read from the pinned version.

## When to revisit
When the homeserver changes its authentication method, or when a password-only deployment must be supported.
