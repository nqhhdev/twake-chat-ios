import Foundation

public enum PushError: Error, Sendable, Equatable {
  case notSignedIn
  case requestFailed
}

/// Registers this device with the homeserver, so that new messages reach it through Apple's push service while the app
/// is closed. Implemented in MatrixData; no SDK type appears here (ADR 0006).
public protocol PushRepository: Sendable {
  /// Registers (or refreshes) this device's pusher with the APNs `deviceToken`. `isProduction` picks the production
  /// APNs app rather than the sandbox one that Debug builds use.
  func register(deviceToken: Data, isProduction: Bool) async throws(PushError)

  /// Removes this device's pusher, so the account stops pushing here (before logging out). Does nothing when none is
  /// registered.
  func unregister() async
}
