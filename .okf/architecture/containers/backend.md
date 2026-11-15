---
type: Container
title: "Backend"
description: "C4 level 2 - the servers the app depends on, as seen from the app."
tags: [c4, container, backend, matrix]
status: draft
---
# Backend

Observed on the public deployment `matrix.linagora.com` on 2026-11-11 (unauthenticated endpoints only). Other
deployments can differ; the app must discover, not assume.

| Service | How the app finds it | What the app uses it for |
|---|---|---|
| Matrix homeserver | `m.homeserver` in `/.well-known/matrix/client` | Sync, rooms, events, media, keys |
| Twake SSO | Login flow `m.login.sso` with identity provider `oidc-twake`; `m.authentication.issuer` in the discovery document | Sign-in ([ADR 0008](../../../docs/adr/0008-authentication-sso-and-discovery.md)) |
| ToM server | `t.server` and `m.identity_server` in the discovery document | Contacts and user info; not used in v1 |
| Twake settings | `app.twake.chat` block in the discovery document (support contact, feature switches) | Read-only feature switches; use in v1 is undecided |
| Push gateway | Build configuration; the Flutter app passes it as `PUSH_NOTIFICATIONS_GATEWAY_URL` | Pusher registration ([ADR 0009](../../../docs/adr/0009-push-gateway-and-nse-decryption.md)) |

## Facts the design relies on
- The homeserver reports Matrix spec versions up to `v1.12`.
- It advertises `org.matrix.simplified_msc3575: true`, the sliding sync variant the Matrix SDK needs
  ([ADR 0003](../../../docs/adr/0003-matrix-rust-sdk.md)).
- Login flows offered: `m.login.sso`, `m.login.token`, `m.login.password`, `m.login.application_service`.

## Not verified
- Whether every Twake deployment the app must support has sliding sync enabled.
- That the push gateway's existing registration for `app.twake.ios.chat` and `app.twake.ios.chat.sandbox` works
  unchanged for the native app.
