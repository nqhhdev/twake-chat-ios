---
type: Workflow
title: "Add a Feature"
description: "The planned procedure for adding a feature across Domain, MatrixData and a feature package."
tags: [feature, procedure]
status: draft
---
# Add a Feature

> Planned procedure; confirm it against the first real feature and correct this page.

1. Check the feature is in scope ([ADR 0011](../adr/0011-v1-scope-core-chat.md)) and read how the Flutter app does it
   (`lib/pages/<feature>` and `lib/domain` in `twake-on-matrix`).
2. **Domain**: add the models and the repository protocol the screens need. Add a use case only if logic spans
   repositories. Write tests for any use case.
3. **MatrixData**: implement the protocol with a proxy; map SDK types and errors. Test the mappers.
4. **Feature package**: add the view model with its tests against fakes, then the screen, then wire it into a coordinator.
5. **DesignSystem**: add a shared component only if a second screen needs it. Put any iOS 18 / 26 difference here, with
   snapshot tests on both versions.
6. **App target**: build the new dependencies in the composition root.
7. Re-read [Constraints](../engineering/constraints.md). Update this knowledge base if something durable changed
   ([Maintain the Knowledge Base](maintain-the-knowledge-base.md)).
