import Foundation

/// How the device owner proves who they are to unlock the app.
public enum DeviceUnlockMethod: Sendable, Equatable {
  case faceID, touchID, opticID, passcode

  /// The name iOS gives it.
  public var name: String {
    switch self {
    case .faceID: "Face ID"
    case .touchID: "Touch ID"
    case .opticID: "Optic ID"
    case .passcode: "Passcode"
    }
  }
}

/// The app lock as Settings shows it (Flutter `AppLock`): on, the app asks for Face ID, Touch ID or the device passcode
/// when it opens and each time it comes back. Implemented by the app.
@MainActor
public protocol AppLockSettings: AnyObject {
  var isEnabled: Bool { get }
  /// `nil` when the device has no passcode, so nothing can lock the app.
  var unlockMethod: DeviceUnlockMethod? { get }
  /// Turns the lock on or off once the owner has proved it is them; `false` when they did not.
  @discardableResult
  func setEnabled(_ enabled: Bool) async -> Bool
}
