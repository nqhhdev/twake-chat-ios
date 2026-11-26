import AppShared
import Foundation
import MatrixData
import SwiftUI

@main
struct TwakeChatApp: App {
  @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
  @State private var accounts: AccountsCoordinator
  @Environment(\.scenePhase) private var scenePhase

  init() {
    MatrixPlatform.setUp()
    guard let registry = AccountRegistry.inAppGroup(),
      let accessGroup = Bundle.main.object(forInfoDictionaryKey: "KeychainAccessGroup") as? String
    else {
      preconditionFailure("The app's entitlements give it no App Group or Keychain access group.")
    }
    let composition = AppComposition(
      registry: registry, accessGroup: accessGroup, appLock: AppLock(),
      badges: AccountBadges.inAppGroup(), calls: AccountCallAvailability.inAppGroup())
    #if DEBUG
      E2EHarness.resetIfAsked(
        storeDirectory: registry.storeDirectory(for: .legacy),
        sessionStore: composition.sessionStore(.legacy), registry: registry)
    #endif
    _accounts = State(
      initialValue: AccountsCoordinator(
        registry: registry,
        legacyUserId: try? composition.sessionStore(.legacy).load()?.userId,
        badges: composition.badges, calls: composition.calls,
        makeRoot: composition.root(for:onSessionChange:)))
  }

  var body: some Scene {
    WindowGroup {
      AccountsView(accounts: accounts)
        .onChange(of: scenePhase) { _, phase in accounts.root.lifecycle.phaseChanged(to: phase) }
        .onChange(of: scenePhase, initial: true) { _, phase in
          accounts.root.appLock?.phaseChanged(to: phase)
        }
        .onOpenURL { url in
          if url == SharedInbox.openURL {
            accounts.openShare()
          } else {
            accounts.root.links.handle(url)
          }
        }
    }
  }
}
