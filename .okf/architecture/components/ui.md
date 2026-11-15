---
type: Component
title: "Features Layer"
description: "C4 level 3 - SwiftUI screens, their view models and the coordinators that route between them."
tags: [c4, component, ui, swiftui]
status: draft
---
# Features Layer

| | |
|---|---|
| Folder | `Packages/Features/<Feature>/` |
| Holds | SwiftUI views, one `@Observable` view model per screen, a coordinator per flow |
| May import | [Domain](domain.md), [Design System](design-system.md) |
| Must not import | [Data](data.md), the Matrix SDK, another feature |

## Shape of a screen
- **View**: a SwiftUI `View` that renders the view model's state and forwards user actions. No logic beyond layout.
- **View model**: `@MainActor @Observable final class`. Receives repository protocols or use cases through its
  initializer, exposes plain state properties and `async` action methods.
- **Coordinator**: owns a `NavigationStack` path and sheet state for one flow, creates view models, and is the only place
  that knows which screen comes next.

A feature never checks the iOS version; that belongs to the [Design System](design-system.md).

Reasoning: [ADR 0004](../../../docs/adr/0004-swiftui-observable-coordinators.md).

## Authentication (built, TWAK-65)
`Packages/Features/Authentication/` holds the password sign-in for Debug builds
([ADR 0019](../../../docs/adr/0019-password-login-debug-builds.md)); SSO and discovery
([ADR 0008](../../../docs/adr/0008-authentication-sso-and-discovery.md)) are not built yet.
- `PasswordLoginScreen` and `PasswordLoginViewModel`: homeserver (prefilled from the Debug build configuration),
  username, password, a loading state and one message per `AuthenticationError`. As in the Flutter app's
  `lib/pages/login/login.dart` `login()`, an empty username or password shows its own message and is not sent, and a
  tap while a sign-in runs does nothing. A homeserver that is not an absolute URL is not sent either.
- `SignedInViewModel`: the signed-in user id and the logout. A logout error keeps the user signed in with an error so
  they can try again. `MatrixAuthenticationRepository` deletes the local session even when the server call fails, so
  trying again then succeeds at once; the user is never shown as signed out while the session is still saved. Its
  screen was removed by TWAK-66: the app shows the chat list for it, and the chat list's Log out runs this logout.
- `AuthenticationCoordinator` and `AuthenticationCoordinatorView`: start from the session restored at launch, switch
  between the sign-in form and the signed-in state and create their view models. The view takes the signed-in
  content from the app (TWAK-66), so this feature does not know the chat list.
- `AuthenticationTestSupport` (a library target of the same package) holds `FakeAuthenticationRepository`, used by
  `AuthenticationTests` and by `TwakeChatTests`. It is not in a Domain test support target, because the TWAK-34/35
  acceptance locks hold Domain to one product and one test target; the owner decides whether to move it when a
  second feature needs it (a feature may not depend on another feature).

The app target's root coordinator, `RootCoordinator` in `TwakeChat/RootView.swift`, restores the saved session once
at launch, then shows `AuthenticationCoordinatorView`. It marks the restore as started before it awaits, since every
window of the app shares it. A restore error of any kind keeps the saved session and its SDK store: the root shows the
feature's `RestoreFailedScreen` with Try again, which restores once more, and Log out, the way out when the error
does not pass (it signs out and shows the sign-in form). The two never run together: Try again shows nothing while
it restores, and Try again does nothing while Log out runs. A Log out error keeps the restore-failed screen with a
message, as on the signed-in screen, since the session may still be saved. The Domain errors cannot tell a session the server rejected
from a fault that passes (a locked Keychain, a held store lock, a 5xx all map to `unknown`), and `logout()` deletes
the store with its encryption keys, so the root never clears a session on its own. This replaces the plan's "a
restore error counts as signed out"; it was accepted on 2026-11-13 under the owner's standing instruction of
2026-11-12, and the owner may still reverse it. Every screen the root shows comes from the feature package, so `RootView.swift` itself holds no `Text` or `Button` (the TWAK-34 lock).
Signed out, the feature opens on `TwakeWelcomeScreen` (linagora-design-flutter `TwakeWelcomeScreen`): Create Twake ID
and Sign in open the registration site, "Use your company server" opens `HomeserverPickerScreen`, which goes to the
server's single SSO provider, to `ConnectScreen` (one button per provider) or to `PasswordLoginScreen` on a server
without SSO, as [ADR 0021](../../../docs/adr/0021-sign-in-as-the-flutter-app.md) says. The feature is the same in Debug and
Release. SSO pages open through the feature's `WebAuthenticator` protocol, which the app implements with
`ASWebAuthenticationSession` (`TwakeChat/SystemWebAuthenticator.swift`). The composition root,
`TwakeChat/TwakeChatApp.swift`, builds `KeychainSessionStore` and `MatrixAuthenticationRepository` and a
`SignInConfiguration` from the `RegistrationURL`, `WorkplaceHomeserver`, `DefaultHomeserver` and `PrivacyURL`
Info.plist keys, which the `TWAKE_*` build settings fill: staging in Debug, Twake SaaS in Release.

## Signed-in shell and room (built)
`TwakeChat/ChatShell.swift` joins the ChatList, Room and Authentication (Settings) features after sign-in. Its
Contacts, Chats and Settings tabs are Apple's system tab view (`TabView`, `.sidebarAdaptable`, ADR 0022) on every
screen, and a chat pushed over the list hides the tab bar; Contacts and the chat list's pencil button are
`Packages/Features/People/` (`PeopleRepository`, `PeopleProxy` in MatrixData): search Twake's address book on the ToM server
(`t.server` in `.well-known`, `POST /_twake/identity/v1/lookup/match` with the access token, as the Flutter
`TomContactAPI` does), then the Matrix user directory, or type a full Matrix id, open the direct chat with someone (the existing one or a new encrypted one), or pick people
and a name for a new private encrypted group; the new chat opens at once. Settings is
`Packages/Features/Settings/` (Domain and DesignSystem only, `AccountSettingsRepository`, `AccountSettingsProxy` in
MatrixData): the profile, Privacy & Security (chat backup: enter the recovery key to unlock old messages, or set up
backup and see the new key once), Notifications (default mode for direct and group chats), About, and Logout with its
confirmation. Chat info also sets the room's own notification mode or its default. The chat list has the Flutter header: the centred "Chats" title and a search field that
filters the rooms by name. The shell lays the screens out by
[ADR 0022](../../../docs/adr/0022-adaptive-layout-flutter-breakpoints.md): one stack under 905 pt (phones, a folded Duo), the
472 pt chat list beside the chat from 905 pt (an unfolded Duo, iPads). `Packages/Features/Room/` (Domain and
DesignSystem only) is the chat: `RoomViewModel` follows the room's `TimelineRepository`, loads older messages, and
sends, replies to, edits, deletes and reacts to messages; `RoomScreen` shows Twake bubbles (own on the right in
`primaryContainer`, others white with the sender's avatar and name), day dividers, room events as one-line notices,
reply quotes and reactions, with the Flutter message menu as a context menu, then `ComposerView`. The timeline groups
messages as Telegram and iMessage do (`TimelineRows`: one sender within 5 minutes; the name on the first bubble, the
avatar and the tail on the last, `TwakeBubbleShape`), and pictures sent together within a minute form an album grid.
It animates: new bubbles spring in from their sender's side, swipe-to-reply with a haptic, double-tap for ❤️ with a
heart burst, reaction chips pop and roll their counts, the send button pops in and bounces, the reply/edit banner
slides up, pictures fade in, and a button returns to the newest message. Pictures, videos and
stickers show a thumbnail at their aspect ratio (at most the bubble width and 300 pt tall); a tap on a picture opens
it full screen with pinch to zoom and Share. Voice messages and files show their name and size; a tap downloads them
(`MediaRepository`, `MediaProxy` in MatrixData) and offers to share or open them. Voice messages and audio play in the bubble (play/pause,
bars that fill and move, time left); videos play full screen with the system player after they download. Holding
the composer's mic records a voice message (slide left to cancel, release to send, with its waveform), sent as a
Matrix voice message; the app asks for the microphone the first time. The composer's "+" (Flutter `PickerType`) sends pictures and videos from the photo library (several at once
arrive as an album) and documents from the Files app, which lists iCloud Drive, Google Drive and any other installed
file provider; uploads go through `TimelineRepository.sendAttachment`. The message menu also pins (a Telegram-style banner under
the header shows the pins, a tap cycles them) and forwards to a chat picked from the chat list (the original content,
media included, without its reply). Messages of only emojis show large without a bubble, and the chat list shows unread
and mention badges. The room shows who is typing above the composer
with bouncing dots, and tells the room when the user types. The room's header opens `RoomDetailsScreen` (the Flutter `chat_details` page): avatar, name, description, address,
encryption, visibility, the members with search, and Leave chat after a confirmation, which closes the chat
(`RoomDetailsRepository`, `RoomDetailsProxy` in MatrixData). `RoomTestSupport` holds `FakeTimelineRepository`,
`FakeMediaRepository` and `FakeRoomDetailsRepository`.

## Chat list (built, TWAK-66)
`Packages/Features/ChatList/` (Domain and DesignSystem only) shows the joined rooms after sign-in, in the order the
`RoomListRepository` gives them (the SDK's, most recent activity first, as the Flutter app's `lib/pages/chat_list`
shows), each with its name and a "sender: text" preview of the last message, and keeps them up to date.
- `ChatListViewModel`: a `loading`, `loaded`, `empty` or `failed` state, started by the screen's `.task` and stopped
  when the screen goes away; Log out runs the closure the app passes in and shows an error when it fails.
- `ChatListScreen`: the list, the empty and error states, and the Log out button.
- `ChatListTestSupport` holds `FakeRoomListRepository`, used by `ChatListTests`.
Unread counts, invitations, archive, avatars, search and spaces are not part of it. The app's `RootCoordinator`
joins the two features: for the signed-in state it builds one `ChatListViewModel` with MatrixData's `RoomListProxy`
and a logout closure that runs `SignedInViewModel.logOut()`.

## The Features index package
`Packages/Features/Package.swift` (with `Sources/Features/Features.swift`, which only imports each feature) is not a
feature and the app does not link it. It depends on every feature package so that a check walking `Packages/*/` can
run `swift build --package-path Packages/Features` and build them all. `scripts/check-architecture.sh` calls it
`FeaturesIndex` and rule 3 lets it depend on feature packages only; for that reason no feature may be called `Sources`.

## Planned features for v1
| Feature | Flutter counterpart (`lib/pages/`) |
|---|---|
| `Authentication` | `twake_welcome`, `homeserver_picker`, `connect`, `login` (password form in Debug built; SSO planned) |
| `ChatList` | `chat_list` |
| `Room` | `chat` (timeline, composer, events) |
| `Encryption` | `bootstrap`, `key_verification`, `chat_encryption_settings` |
| `Settings` | `settings_dashboard` (sign-out and the minimum needed) |
