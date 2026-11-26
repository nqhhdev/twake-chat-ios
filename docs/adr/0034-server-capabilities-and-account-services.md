---
type: ADR
title: "ADR 0034: One read of the server's capabilities; account services built on it"
description: "Proposed: a ServerCapabilities value, read after sign-in from the well-known, /versions and the build settings, is the only place a feature learns which non-Matrix service exists; delete account, help, language, analytics and the app grid follow it."
tags: [adr, server, discovery, settings]
status: draft
---
# ADR 0034: One read of the server's capabilities; account services built on it

**Status:** Proposed, 2026-11-25, for the owner's review. Implements [ADR 0026](0026-matrix-first-client-server-features.md)
(Proposed) for issues #192, #170, #171, #172, #173 and #174, under the owner's direction of 2026-11-25 to decide
without asking.

## Context
ADR 0026 says a feature that needs a non-Matrix service shows only when the server or the build announces it. Before
this change, contacts lookup, contacts visibility, the recovery vault and Meet each read `.well-known/matrix/client`
on their own, with their own decoder. Five Settings features were missing: delete account, help and the support chat,
the language of the Twake common settings, analytics with consent, and the app grid of the Twake apps.

## Decision
1. **`ServerCapabilities`** (Domain) is the one answer to "what does this account's server offer". It holds the
   homeserver and identity server URLs, ToM (`app.twake.tom`, else `t.server`, with its server name), the LiveKit
   call foci (`org.matrix.msc4143.rtc_foci`), the `app.twake.chat` keys (`support_contact`,
   `common_settings.application_url` unless `enabled` is false, `enable_invitations`, `side_service` or the former
   `assistants`, `web_url`), the `/_matrix/client/versions` `unstable_features` that are `true`, and the build
   services (`BuildServices`: support URL, analytics switch and URL, the app grid list). The keys are read as the web
   client's `parseTwakeServices` reads them.
2. **`ServerCapabilitiesRepository`** (`current()`, `refresh()`) is implemented by `ServerCapabilitiesProxy`
   (MatrixData). The well-known is read at the user's server name, as before. The answer is kept in memory per
   account; `current()` loads it once, concurrent calls share one load, and the signed-in screen calls `refresh()` at
   each launch and sign-in. Signed out, only the build services are returned, and nothing is requested.
3. Contacts lookup, contacts visibility, the recovery vault and Meet take ToM and the call foci from it. Their
   behaviour does not change, except that the newer `app.twake.tom` key is read before `t.server`, as the web does.
   The identity service keeps its own discovery (ADR 0029, owned by another change).
4. **Delete account (#170).** When `common_settings.application_url` holds `{username}`, the row opens that page with
   the user's localpart, as Flutter's `completedApplicationUrl`. Otherwise the app asks for a destructive
   confirmation and calls `POST /_matrix/client/v3/account/deactivate` with `erase: false`, using the same
   user-interactive authentication as signing devices out (SSO fallback page or password). On success the local
   session and store are removed and the welcome screen shows. Flutter mails support instead on a server without
   common settings; Matrix deactivation replaces it because Apple requires in-app account deletion.
5. **Help (#171).** The Help row opens the build setting `TWAKE_SUPPORT_URL` (`https://twake.app/support` in both
   configurations, from Flutter's `support_url`). "Chat with Support" opens the direct chat with `support_contact`
   through the existing direct-chat opener, so the chat found in `m.direct` is reused on every device; Flutter's
   `app.twake.support_room` account data is not written.
6. **Language (#172).** At each sign-in the app reads `language` from ToM `GET /_twake/v1/user_info/{userId}`. A
   language the app is localised in (`Bundle.main.localizations`) is written to the app's `AppleLanguages`, which iOS
   applies from the next launch, and remembered as applied by the app. Without ToM, the device language comes back
   only if the app had set one; a language the user chose in iOS Settings is left alone. When ToM is there but does not
   answer, nothing changes.
7. **Analytics (#173).** Off unless the build sets `TWAKE_ANALYTICS_ENABLED = YES` (`NO` in both configurations
   today). The endpoint follows the web's current contract (`docs/analytics.md`, D404, D405), which replaces the ToM
   path ADR 0026 assumed: `POST {side_service}/analytics/events`, or `TWAKE_ANALYTICS_URL` when set, with a Matrix
   OpenID token and `x-matrix-server-name`, body `{app, version, events}`. The consent is the web's account data
   `app.twake.chat.analytics_consent` (`{granted, at}`), so a choice made on one device holds on all. The user is asked
   once in a sheet after sign-in and can change it in Settings; nothing is kept or sent before a yes, and a no drops
   what waits. Only `session_started` and `analytics_consent_given` are sent for now; the rest of the web catalogue is
   follow-up work.
8. **App grid (#174).** `TWAKE_APP_GRID_FILE` names a JSON list bundled in the app (`TwakeApps.json`: Twake Mail,
   Twake Drive, from Flutter's `app_dashboard.json`). An empty setting or list hides the row. The grid opens from a
   "Twake Apps" row in Settings, not from the chat list bar as in Flutter, to keep the chat list untouched while it is
   being reworked.

## Consequences
**Good.** One place to read, cache and test server announcements; a plain Synapse sees none of the Twake rows and
receives no `/_twake` request beyond the well-known read. **Costly.** A capability that changes on the server is seen
at the next launch or sign-in. **Alternatives rejected.** Persisting the capabilities on disk: an offline launch
already works, since each feature hides what it cannot reach. Analytics through ToM as ADR 0026 wrote: the web moved
to the side service and ToM has no endpoint. A Flutter-style PIN-less support room in account data: the direct chat
already gives the same room on every device.

## When to revisit
When the owner accepts ADR 0026, when the web changes its analytics contract, or when the chat list rework is done
(the app grid button can then move to the chat list bar).
