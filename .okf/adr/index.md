Architecture Decision Records - why the codebase is the way it is.

Every page is a draft. "Accepted" in a page means the project owner chose it; "Proposed" means it waits for their decision.
Supersede an accepted ADR rather than editing it.

# Concepts
* [ADR 0001: Record architecture decisions](0001-record-architecture-decisions.md) - Decisions that are expensive to reverse are written as numbered ADRs in this folder.
* [ADR 0002: Minimum iOS 18, iOS 26 styling isolated in the Design System](0002-ios-18-minimum-ios-26-styling.md) - The app deploys to iOS 18 and adopts iOS 26 Liquid Glass only inside the DesignSystem package.
* [ADR 0003: Use the Matrix Rust SDK through its Swift package](0003-matrix-rust-sdk.md) - The app is built on matrix-rust-sdk's Swift bindings, which requires sliding sync on the homeserver.
* [ADR 0004: SwiftUI with Observable view models and coordinators](0004-swiftui-observable-coordinators.md) - Screens are SwiftUI views driven by one @Observable view model each; coordinators own navigation.
* [ADR 0005: Layers as local Swift packages](0005-layered-local-swift-packages.md) - Features, Domain, MatrixData, DesignSystem and AppShared are separate local packages so import rules are compile errors.
* [ADR 0006: The Matrix SDK is reached only through proxy protocols](0006-sdk-behind-proxy-protocols.md) - MatrixData wraps each SDK object in a proxy that implements a Domain protocol; no SDK type leaves that package.
* [ADR 0007: One session store shared by the app and the extension](0007-shared-session-store-app-group.md) - The SDK store lives in the App Group container and tokens in a shared Keychain group, read by both processes.
* [ADR 0008: Sign in with SSO after server discovery](0008-authentication-sso-and-discovery.md) - The app discovers the homeserver from its well-known document and signs in through the system web authentication session.
* [ADR 0009: Push through the existing gateway, decrypted in the extension](0009-push-gateway-and-nse-decryption.md) - The app registers an APNs pusher on the homeserver via the Twake push gateway; the extension fetches and decrypts the event.
* [ADR 0010: Test logic with fakes and UI on both iOS versions](0010-testing-strategy-two-ios-versions.md) - View models and use cases are unit-tested against fake proxies; shared components are checked on iOS 18 and iOS 26 simulators.
* [ADR 0011: Version 1 is core chat only](0011-v1-scope-core-chat.md) - v1 ships sign-in, chat list, timeline, encryption recovery and push; every other Flutter feature is deferred.
* [ADR Template](_template-adr.md) - Copy this when recording an architecture decision.
* [ADR 0012: Reuse the Flutter app's bundle identifier](0012-reuse-flutter-bundle-identifier.md) - The native app ships as app.twake.ios.chat, so it installs over the Flutter app instead of beside it.
* [ADR 0014: CI on GitHub Actions with GitHub-hosted macOS runners; swift-format for formatting and lint](0014-ci-github-actions-swift-format.md) - CI runs on GitHub Actions macOS runners like the Flutter app, and swift-format from Xcode formats and lints; billed macOS minutes are the price.
* [ADR 0015: Pin matrix-rust-components-swift at exactly 26.04.01](0015-pin-matrix-rust-components-swift-26-04-01.md) - The SDK package is pinned to 26.04.01, the version the Flutter app's extension uses; it is older than Element X, so API names come from the pinned package.
* [ADR 0019: Offer password login in Debug builds only](0019-password-login-debug-builds.md) - Debug builds sign in with m.login.password against the staging homeserver behind #if DEBUG; Release stays SSO-only as ADR 0008 says.
* [ADR 0020: Integration tests against staging are opt-in and local only](0020-opt-in-local-staging-integration-tests.md) - Integration tests read staging credentials at run time from a local env file or environment variables, skip when they are absent, and never run in CI.
