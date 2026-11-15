---
type: ADR
title: "ADR 0021: Sign in exactly as the Flutter app does"
description: "TwakeWelcome first; Twake ID through the registration site, company servers through discovery, SSO via the web session and the loginToken; password only on a server without SSO, in every build."
tags: [adr, authentication, sso, security]
status: draft
---
# ADR 0021: Sign in exactly as the Flutter app does

**Status:** Decided under the project owner's delegation ("migrate everything to iOS, no decision needed from me"),
2026-11-13; for the owner's review. Supersedes [ADR 0019](0019-password-login-debug-builds.md). Amends
[ADR 0008](0008-authentication-sso-and-discovery.md).

## Context
The owner tried the Debug build and rejected its sign-in: the app opened on a password form, while Twake Chat signs in
through SSO and opens on TwakeWelcome. The owner asked for the flow of twake-on-matrix itself. Read at the pinned
baseline ([ADR 0013](0013-flutter-baseline-and-feature-status.md)):
- `lib/config/routes/app_routes.dart:166`: signed out, mobile opens `TwakeWelcome`.
- `lib/pages/twake_welcome/twake_welcome.dart:62-139`: Sign in and Create Twake ID open `registration_url` with
  `post_login_redirect_url` (or `post_registered_redirect_url`) `twake.chat://redirect` and `app=chat` in a web
  authentication session, then sign in to `twake_workplace_homeserver` with the returned `loginToken`
  (`lib/pages/connect/connect_page_mixin.dart:329-342`).
- `lib/pages/homeserver_picker/homeserver_picker.dart:146-243`: "Use your company server" cleans the typed server,
  reads its login flows and probes registration; no SSO goes to the password form, SSO with no registration and one
  identity provider opens `<homeserver>/_matrix/client/r0/login/sso/redirect/<idp>?redirectUrl=twake.chat://login`,
  anything else shows the connect page.
- `config.json` (staging) and `lib/config/config_saas/config_saas.dart` (Twake SaaS) give the URLs.

The pinned SDK ([ADR 0015](0015-pin-matrix-rust-components-swift-26-04-01.md)) has `Client.startSsoLogin` and
`SsoHandler.finish(callbackUrl:)`, which reads the `loginToken` from the callback, but no list of identity providers.

## Decision
- The signed-out first screen is TwakeWelcome, laid out as linagora-design-flutter `TwakeWelcomeScreen`.
- Twake ID (Sign in, Create Twake ID): MatrixData starts an SSO sign-in on the workplace homeserver to get the SDK
  handler; the registration site opens in `ASWebAuthenticationSession` with callback scheme `twake.chat`; the
  callback finishes the handler.
- Company server: MatrixData reads `.well-known/matrix/client`, `GET /_matrix/client/v3/login` (flows and identity
  providers) and an empty `POST /_matrix/client/v3/register` (401 means registration) over plain HTTP, then follows
  the Flutter routing above. Its SSO uses `startSsoLogin(redirectUrl: "twake.chat://login", idpId:)`.
- Password sign-in exists in Debug and Release, reached only for a server without SSO, as in the Flutter app.
  `#if DEBUG` gating of the Authentication feature is removed.
- The sign-in URLs are build settings read through Info.plist: Debug uses the staging `config.json` values, Release
  the Twake SaaS ones. The app registers the `twake.chat` and `matrix` URL schemes.
- `ASWebAuthenticationSession` lives in the app target behind the feature's `WebAuthenticator` protocol, because a
  feature imports only what [ADR 0005](0005-layered-local-swift-packages.md) allows.

## Consequences
**Good.** Sign-in matches what Twake Chat users know, on staging and SaaS, and Release can sign in. **Costly.** The
app holds a password in every build (only for servers without SSO), and discovery is a second HTTP client beside the
SDK. **Open, to verify by hand:** that the registration site's `loginToken` finishes a handler started on the
workplace homeserver (the SDK reads only the token from the callback); the SSO sign-out of
`connect_page_mixin.dart:95-100` (`<issuer>?logout=1`) is not built yet.
