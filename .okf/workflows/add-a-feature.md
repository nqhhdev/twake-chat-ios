---
type: Workflow
title: "Add a Feature"
description: "How to add a feature across Domain, MatrixData, a feature package and the app target, as Authentication was built."
tags: [feature, procedure]
status: draft
---
# Add a Feature

Checked against the first feature, `Authentication` (TWAK-65).

1. Check the feature is in scope ([ADR 0011](../../docs/adr/0011-v1-scope-core-chat.md)) and read how the Flutter app does it
   (`lib/pages/<feature>` and `lib/domain` in `twake-on-matrix`).
2. **Domain**: add the models and the repository protocol the screens need. Add a use case only if logic spans
   repositories. Write tests for any use case.
3. **MatrixData**: implement the protocol with a proxy; map SDK types and errors. Test the mappers.
4. **Feature package**: create `Packages/Features/<Feature>/Package.swift` (tools 6.2, `.iOS(.v18)`,
   `.treatAllWarnings(as: .error)` on every target) depending only on `.package(path: "../../Domain")` and
   `.package(path: "../../DesignSystem")`; `scripts/check-architecture.sh` rule 3 rejects anything else. Add the view
   model with its tests against fakes, then the screen, then wire it into a coordinator. Put each `Fake<Protocol>` in
   a `<Feature>TestSupport` library target of the same package, so the app's tests can link it too.
   The package declares iOS only, so its tests run in the test plan on the simulator, not with host `swift test`.
   Also add it to `Packages/Features/Package.swift`, which is not a feature: it only depends on every feature
   package, so that `swift build --package-path Packages/Features` (a check that walks `Packages/*/`) builds them all;
   the architecture check lets that index depend on feature packages only (see the Features Layer page).
5. **DesignSystem**: add a shared component only if a second screen needs it. Put any iOS 18 / 26 difference here, with
   snapshot tests on both versions.
6. **App target**: in `TwakeChat.xcodeproj`, add an `XCLocalSwiftPackageReference` for the package, link its product
   to `TwakeChat` (and its test support product to `TwakeChatTests` if they use it), and add
   `container:Packages/Features/<Feature>` / `<Feature>Tests` to `TwakeChat.xctestplan`. Build the new dependencies
   in the composition root (`TwakeChat/TwakeChatApp.swift`) and show the flow from the root coordinator
   (`TwakeChat/RootView.swift`). A Debug-only feature wraps each of its source files in `#if DEBUG`, since the
   product is linked in Release; build-configuration values go in a build setting read through an `Info.plist` key,
   never a secret.
7. Re-read [Constraints](../engineering/constraints.md). Update this knowledge base if something durable changed
   ([Maintain the Knowledge Base](maintain-the-knowledge-base.md)).
