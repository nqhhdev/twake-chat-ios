import Domain
import Foundation
import SwiftUI
import Testing

@testable import TwakeChat

/// The app lock: when it locks, when it asks, and that changing it needs the owner.
@MainActor
struct AppLockTests {
  /// Face ID that passes or fails as the test says, counting its prompts.
  private final class FakeCheck: DeviceOwnerCheck, @unchecked Sendable {
    var available: DeviceUnlockMethod? = .faceID
    var passes = true
    var prompts = 0
    func method() -> DeviceUnlockMethod? { available }
    func authenticate(reason: String) async -> Bool {
      prompts += 1
      return passes
    }
  }

  private let suite = "AppLockTests-\(UUID().uuidString)"

  private func lock(_ check: FakeCheck, enabled: Bool) -> AppLock {
    let defaults = UserDefaults(suiteName: suite)!
    defaults.set(enabled, forKey: AppLock.enabledKey)
    return AppLock(check: check, defaults: defaults)
  }

  private func settle() async {
    for _ in 0..<20 { await Task.yield() }
  }

  @Test func offItNeitherLocksNorCovers() async {
    defer { UserDefaults().removePersistentDomain(forName: suite) }
    let check = FakeCheck()
    let lock = lock(check, enabled: false)
    lock.phaseChanged(to: .background)
    lock.phaseChanged(to: .active)
    await settle()
    #expect(!lock.isLocked && !lock.isCovered)
    #expect(check.prompts == 0)
  }

  @Test func onItLocksAtLaunchAndAsksOnceActive() async {
    defer { UserDefaults().removePersistentDomain(forName: suite) }
    let check = FakeCheck()
    let lock = lock(check, enabled: true)
    #expect(lock.isLocked)
    lock.phaseChanged(to: .active)
    await settle()
    #expect(check.prompts == 1)
    #expect(!lock.isLocked)
  }

  @Test func goingToTheBackgroundLocksAndCovers() async {
    defer { UserDefaults().removePersistentDomain(forName: suite) }
    let check = FakeCheck()
    let lock = lock(check, enabled: true)
    lock.phaseChanged(to: .active)
    await settle()
    lock.phaseChanged(to: .inactive)
    #expect(lock.isCovered && !lock.isLocked)
    lock.phaseChanged(to: .background)
    #expect(lock.isCovered && lock.isLocked)
    lock.phaseChanged(to: .active)
    await settle()
    #expect(check.prompts == 2)
    #expect(!lock.isCovered && !lock.isLocked)
  }

  @Test func aFailedTryStaysLockedAndDoesNotAskAgainByItself() async {
    defer { UserDefaults().removePersistentDomain(forName: suite) }
    let check = FakeCheck()
    check.passes = false
    let lock = lock(check, enabled: true)
    lock.phaseChanged(to: .active)
    await settle()
    // The system prompt made the app inactive; coming back active must not prompt again.
    lock.phaseChanged(to: .inactive)
    lock.phaseChanged(to: .active)
    await settle()
    #expect(check.prompts == 1)
    #expect(lock.isLocked)
    check.passes = true
    await lock.unlock()
    #expect(!lock.isLocked)
  }

  @Test func changingItNeedsTheOwner() async {
    defer { UserDefaults().removePersistentDomain(forName: suite) }
    let check = FakeCheck()
    let lock = lock(check, enabled: false)
    check.passes = false
    #expect(await lock.setEnabled(true) == false)
    #expect(!lock.isEnabled)
    check.passes = true
    #expect(await lock.setEnabled(true))
    #expect(lock.isEnabled)
    #expect(UserDefaults(suiteName: suite)!.bool(forKey: AppLock.enabledKey))
  }

  @Test func withoutAPasscodeItCannotBeTurnedOnAndALockedAppOpens() async {
    defer { UserDefaults().removePersistentDomain(forName: suite) }
    let check = FakeCheck()
    check.available = nil
    let off = lock(check, enabled: false)
    #expect(await off.setEnabled(true) == false)
    let on = lock(check, enabled: true)
    await on.unlock()
    #expect(!on.isLocked && !on.isEnabled)
    #expect(check.prompts == 0)
  }
}
