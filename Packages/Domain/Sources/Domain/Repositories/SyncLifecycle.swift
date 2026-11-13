import Foundation

/// Pauses and resumes the signed-in client's sync with the app's life: iOS suspends an app soon after it leaves the
/// screen, so sync stops cleanly instead of being frozen mid-request, and starts again when the app comes back. The
/// screens' room lists and timelines stay as they are and update again on resume. Implemented in MatrixData; no SDK type
/// appears here (ADR 0006).
public protocol SyncLifecycle: Sendable {
  func pauseSync() async
  func resumeSync() async
}
