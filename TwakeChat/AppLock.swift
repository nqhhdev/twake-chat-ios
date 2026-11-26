import DesignSystem
import Domain
import LocalAuthentication
import SwiftUI

/// Proves the device owner: Face ID, Touch ID or the device passcode. Tests pass a fake.
protocol DeviceOwnerCheck: Sendable {
  /// `nil` when the device has no passcode.
  func method() -> DeviceUnlockMethod?
  func authenticate(reason: String) async -> Bool
}

/// The system's check (LocalAuthentication), biometrics first with the passcode as fallback.
struct SystemDeviceOwnerCheck: DeviceOwnerCheck {
  func method() -> DeviceUnlockMethod? {
    let context = LAContext()
    var error: NSError?
    guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { return nil }
    switch context.biometryType {
    case .faceID: return .faceID
    case .touchID: return .touchID
    case .opticID: return .opticID
    default: return .passcode
    }
  }

  func authenticate(reason: String) async -> Bool {
    let context = LAContext()
    return (try? await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason))
      ?? false
  }
}

/// The app lock (Flutter `AppLock` with its PIN screen). The device owner's Face ID, Touch ID or passcode replaces the
/// app's own four-digit PIN, so no secret is stored. On, the app is locked when it opens and when it goes to the
/// background, and asks once when it comes back; a failed or cancelled try leaves the lock screen with its Unlock
/// button. While the app is not active its content is covered, so the app switcher does not show the chats.
@MainActor @Observable
final class AppLock: AppLockSettings {
  static let enabledKey = "app.twake.ios.chat.appLock.isEnabled"

  private(set) var isEnabled: Bool
  /// The lock screen covers the app.
  private(set) var isLocked: Bool
  /// The app is not active and the lock is on: its content is covered.
  private(set) var isCovered = false
  private(set) var isUnlocking = false
  /// The next time the app is active, ask at once: after a launch or a return, not after a failed try.
  @ObservationIgnored private var asksWhenActive: Bool
  @ObservationIgnored private let check: any DeviceOwnerCheck
  @ObservationIgnored private let defaults: UserDefaults

  init(check: any DeviceOwnerCheck = SystemDeviceOwnerCheck(), defaults: UserDefaults = .standard) {
    self.check = check
    self.defaults = defaults
    let enabled = defaults.bool(forKey: Self.enabledKey)
    isEnabled = enabled
    isLocked = enabled
    asksWhenActive = enabled
  }

  var unlockMethod: DeviceUnlockMethod? { check.method() }

  func phaseChanged(to phase: ScenePhase) {
    guard isEnabled else {
      isCovered = false
      return
    }
    switch phase {
    case .background:
      isCovered = true
      isLocked = true
      asksWhenActive = true
    case .inactive:
      isCovered = true
    case .active:
      isCovered = false
      if isLocked, asksWhenActive {
        asksWhenActive = false
        Task { await unlock() }
      }
    @unknown default:
      break
    }
  }

  /// Asks the owner and opens the app when they pass. A device that no longer has a passcode cannot prove anyone, so
  /// the lock turns off rather than keep the owner out.
  func unlock() async {
    guard isLocked, !isUnlocking else { return }
    guard check.method() != nil else {
      store(false)
      isLocked = false
      return
    }
    isUnlocking = true
    defer { isUnlocking = false }
    if await check.authenticate(reason: String(localized: "Unlock Twake Chat")) {
      withAnimation(.easeOut(duration: 0.25)) { isLocked = false }
    }
  }

  @discardableResult
  func setEnabled(_ enabled: Bool) async -> Bool {
    guard enabled != isEnabled else { return true }
    guard check.method() != nil,
      await check.authenticate(
        reason: enabled
          ? String(localized: "Turn on App Lock") : String(localized: "Turn off App Lock"))
    else { return false }
    store(enabled)
    return true
  }

  private func store(_ enabled: Bool) {
    isEnabled = enabled
    defaults.set(enabled, forKey: Self.enabledKey)
  }
}

/// What covers the app while it is locked or not on screen: the Twake logo and, when locked, the unlock button named
/// after the device's method.
struct AppLockScreen: View {
  let lock: AppLock

  var body: some View {
    VStack(spacing: 24) {
      Spacer()
      TwakeLogo(TwakeLogo.welcomeResource)
      if lock.isLocked {
        Text("Twake Chat is locked")
          .font(.headline)
          .foregroundStyle(SysColors.textSecondary)
        Button {
          Task { await lock.unlock() }
        } label: {
          Label("Unlock", systemImage: symbol)
            .frame(minWidth: 160)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(lock.isUnlocking)
      }
      Spacer()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(SysColors.background)
  }

  private var symbol: String {
    switch lock.unlockMethod {
    case .faceID: "faceid"
    case .touchID: "touchid"
    case .opticID: "opticid"
    case .passcode, nil: "lock.open"
    }
  }
}
