---
type: System Context
title: "System Context"
description: "C4 level 1 - what this app is, who uses it, and which external systems it depends on."
tags: [c4, context, ios]
status: draft
---
# System Context

> Design stage: no app code exists yet. This page describes the intended system. Rows marked **verify** are not confirmed.

## The system
Twake Chat for iOS is a native Swift chat client for the [Matrix](https://spec.matrix.org) protocol. It is the native
counterpart of the Flutter Twake Chat app (`twake-on-matrix`) and talks to the same servers. It runs on iPhone, on
iOS 18 and iOS 26 ([ADR 0002](../../docs/adr/0002-ios-18-minimum-ios-26-styling.md)).

The scope is parity with the Flutter app and the Twake web client on any Matrix homeserver; features that need a Twake
service show only where the server announces it ([ADR 0026](../../docs/adr/0026-matrix-first-client-server-features.md),
Proposed, to supersede [ADR 0011](../../docs/adr/0011-v1-scope-core-chat.md)'s core-chat v1).

## Who uses it
| Actor | Interaction |
|---|---|
| Twake Workplace user | Signs in with their Twake account and chats, using the [App](containers/app.md) |
| The same user on another client | Uses the Flutter or web app on the same account; rooms, messages and keys must stay consistent |

## External systems
| System | Role | Status |
|---|---|---|
| Matrix homeserver (Synapse) | Source of truth for rooms, events, keys and media. See [Backend](containers/backend.md) | Exists |
| Twake SSO (OpenID Connect provider) | Authenticates the user; the homeserver exposes it as an SSO identity provider | Exists |
| ToM server (`t.server` / identity server in the discovery document) | Twake additions on top of Matrix: contacts lookup, user info | Exists; not used in v1 |
| Push gateway (Sygnal) and APNs | Delivers push notifications to the device | Exists; app registration for this app is **verify** |
| Crash and error reporting | The Flutter app can be built with Sentry | Not decided for this app |

## Boundaries
This repository is the iOS client only. The servers, the Flutter app and the web app are out of scope. The Matrix SDK is a
binary dependency, not part of this repository ([ADR 0003](../../docs/adr/0003-matrix-rust-sdk.md)).
