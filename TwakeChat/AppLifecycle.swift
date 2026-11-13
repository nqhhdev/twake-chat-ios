import Domain
import SwiftUI
import UIKit
import UserNotifications

/// The app's life in the background and foreground. Going to the background, sync keeps running for a short grace period
/// (a background task, so a message being sent finishes) and is then paused; the app icon badge shows the unread count.
/// Coming back, sync resumes at once and the device token is refreshed. Without a lifecycle (tests), it does nothing.
@MainActor
final class AppLifecycle {
  /// How long sync keeps running once the app leaves the screen.
  static let gracePeriod: Duration = .seconds(20)

  private let sync: (any SyncLifecycle)?
  private let push: PushCenter
  /// The unread messages of all chats, for the badge.
  var unreadCount: () -> Int = { 0 }
  private var pausing: Task<Void, Never>?
  private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
  private var isPaused = false

  init(sync: (any SyncLifecycle)?, push: PushCenter) {
    self.sync = sync
    self.push = push
  }

  func phaseChanged(to phase: ScenePhase) {
    switch phase {
    case .active: enterForeground()
    case .background: enterBackground()
    default: break
    }
  }

  private func enterForeground() {
    pausing?.cancel()
    pausing = nil
    endBackgroundTask()
    if isPaused {
      isPaused = false
      Task { await sync?.resumeSync() }
    }
    // A token can change between launches; asking again re-registers the pusher with the current one.
    Task { await push.refreshToken() }
  }

  private func enterBackground() {
    Task { try? await UNUserNotificationCenter.current().setBadgeCount(unreadCount()) }
    guard sync != nil, pausing == nil else { return }
    backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Sync") { [weak self] in
      MainActor.assumeIsolated { self?.pauseNow() }
    }
    pausing = Task { [weak self] in
      try? await Task.sleep(for: Self.gracePeriod)
      guard !Task.isCancelled else { return }
      self?.pauseNow()
    }
  }

  private func pauseNow() {
    pausing?.cancel()
    pausing = nil
    guard !isPaused else { return }
    isPaused = true
    Task { [weak self] in
      await self?.sync?.pauseSync()
      self?.endBackgroundTask()
    }
  }

  private func endBackgroundTask() {
    guard backgroundTask != .invalid else { return }
    UIApplication.shared.endBackgroundTask(backgroundTask)
    backgroundTask = .invalid
  }
}
