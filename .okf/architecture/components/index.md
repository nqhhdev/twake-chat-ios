C4 level 3 - the modules inside the app and what each may import. Level 4 is the code itself: link real files from each page once they exist.

Each layer is a local Swift package, so a forbidden import fails to compile ([ADR 0005](../../../docs/adr/0005-layered-local-swift-packages.md)).

```
Features  ->  Domain  <-  MatrixData  ->  Matrix SDK
   |                          |
   v                          v
DesignSystem               AppShared

App target and Notification Service Extension: composition roots, may import everything they need.
```

# Concepts
* [Data Layer](data.md) - C4 level 3 - the only module that imports the Matrix SDK; implements the Domain repository protocols.
* [Design System](design-system.md) - C4 level 3 - colours, typography and shared components; the only place that branches on the iOS version.
* [Domain Layer](domain.md) - C4 level 3 - app models, repository protocols and use cases, free of SwiftUI and of the Matrix SDK.
* [Features Layer](ui.md) - C4 level 3 - SwiftUI screens, their view models and the coordinators that route between them.
