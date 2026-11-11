How to write one more of something. One page per pattern the repo actually uses; copy the template.

# Chosen patterns
Each row is decided by an ADR. Pattern pages with real code are added when the first example exists.

| Concern | Choice | Decided in |
|---|---|---|
| State and dependency injection | `@Observable` view models; initializer injection from a composition root | [ADR 0004](../../adr/0004-swiftui-observable-coordinators.md) |
| Navigation | Coordinators owning `NavigationStack` paths | [ADR 0004](../../adr/0004-swiftui-observable-coordinators.md) |
| Expected failures | Typed Domain errors thrown from `async throws` functions | [ADR 0006](../../adr/0006-sdk-behind-proxy-protocols.md) |
| Access to Matrix | Proxies in `MatrixData` behind Domain protocols | [ADR 0006](../../adr/0006-sdk-behind-proxy-protocols.md) |
| Local storage | The SDK store and the Keychain only | [ADR 0007](../../adr/0007-shared-session-store-app-group.md) |
| Test doubles | Hand-written fakes | [ADR 0010](../../adr/0010-testing-strategy-two-ios-versions.md) |
| Project structure | Local Swift packages per layer and per feature | [ADR 0005](../../adr/0005-layered-local-swift-packages.md) |
| iOS version differences | Adaptive modifiers in `DesignSystem` | [ADR 0002](../../adr/0002-ios-18-minimum-ios-26-styling.md) |

# Concepts
* [Pattern Template](_template-pattern.md) - Copy this when documenting how to write one more of something.
