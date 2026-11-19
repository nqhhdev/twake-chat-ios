import Foundation

/// Tells the app when the homeserver stops accepting this device's session for good: the device was signed out from
/// another one, or by an administrator. The saved session and its store are then useless, so the app removes them and
/// shows the sign-in form instead of a chat list that never updates. Implemented in MatrixData; no SDK type appears
/// here (ADR 0006).
public protocol SessionExpiry: Sendable {
  /// Yields once each time the server refuses the session's token and the session cannot be refreshed. A token the
  /// server asks to renew (a soft logout) does not yield: the device still exists there.
  func sessionExpirations() async -> AsyncStream<Void>
}
