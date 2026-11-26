import Foundation
import MatrixRustSDK

enum StoreLock {
  static let retryPause: Duration = .milliseconds(250)
  static let timeout: Duration = .seconds(20)

  static func isTimeout(_ error: any Error) -> Bool {
    (error as? ClientError).map(isLockTimeout) ?? false
  }

  static func isLockTimeout(_ error: ClientError) -> Bool {
    guard case .Generic(_, let details?) = error else { return false }
    return details.contains("Unobtained(TimedOut)")
  }

  static func retrying<T>(
    timeout: Duration = timeout, pause: Duration = retryPause,
    isTimeout: (any Error) -> Bool = isTimeout,
    sleep: (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
    _ work: () async throws -> T
  ) async throws -> T {
    let deadline = ContinuousClock.now + timeout
    while true {
      do {
        return try await work()
      } catch  where isTimeout(error) && ContinuousClock.now + pause < deadline {
        try Task.checkCancellation()
        try await sleep(pause)
      }
    }
  }
}
