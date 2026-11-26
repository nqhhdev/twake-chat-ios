import Authentication
import ChatList
import DesignSystem
import Domain
import Foundation
import Observation
import People
import Room
import Settings
import SwiftUI

/// The app's root view: it only shows what the root coordinator holds.
struct RootView: View {
  let coordinator: RootCoordinator

  var body: some View {
    content
      .task { await coordinator.start() }
      .alert(
        "You were signed out",
        isPresented: Binding(
          get: { coordinator.sessionExpiredNotice },
          set: { coordinator.sessionExpiredNotice = $0 })
      ) {
        Button("OK", role: .cancel) {}
      } message: {
        Text("This device was signed out from another device. Sign in again to continue.")
      }
      .overlay {
        if let lock = coordinator.appLock, lock.isLocked || lock.isCovered {
          AppLockScreen(lock: lock).transition(.opacity)
        }
      }
  }

  /// The screens come from the Authentication and ChatList feature packages.
  @ViewBuilder private var content: some View {
    if coordinator.state == .restoreFailed {
      RestoreFailedScreen(
        errorMessage: coordinator.logOutErrorMessage,
        retry: { Task { await coordinator.start() } },
        logOut: { Task { await coordinator.logOutAfterFailedRestore() } })
    } else if let authentication = coordinator.authentication {
      AuthenticationCoordinatorView(coordinator: authentication) { signedIn in
        if let chatList = coordinator.chatList(for: signedIn) {
          ChatShell(
            chatList: chatList, signedIn: signedIn, settings: coordinator.settings(for: signedIn),
            push: coordinator.push, links: coordinator.links, shares: coordinator.shares,
            makePeopleSearch: coordinator.peopleSearch(mode:onOpen:),
            makeRoom: coordinator.room(for:onLeft:),
            checkSession: coordinator.sessionCheckAfterUnlock(),
            meetCalls: coordinator.meetCalls, roomCalls: coordinator.roomCalls,
            makePhoneContacts: coordinator.phoneContacts,
            makeTwakeContacts: coordinator.twakeContacts
          )
          // Signed in: ask for notifications and register this device.
          .task { await coordinator.push.start() }
          .task { await coordinator.unlockDevice(for: signedIn) }
          .task { await coordinator.capabilities?.refresh() }
          .task { await coordinator.applyCommonSettingsLanguage() }
          .usageAnalyticsPrompt(
            coordinator.settings(for: signedIn).usageAnalytics,
            isBlocked: coordinator.unsavedRecoveryKey != nil
          )
          .sheet(
            isPresented: Binding(
              get: { coordinator.unsavedRecoveryKey != nil },
              set: { if !$0 { coordinator.unsavedRecoveryKey = nil } })
          ) {
            if let key = coordinator.unsavedRecoveryKey {
              RecoveryKeySheet(key: key) { coordinator.unsavedRecoveryKey = nil }
            }
          }
        }
      }
    } else {
      // Restoring the saved session at launch: the Twake logo, as the Flutter app's splash shows it.
      TwakeLogo(TwakeLogo.welcomeResource)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SysColors.background)
    }
  }
}
