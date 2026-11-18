import Foundation

/// The work did not finish before the time it was given.
struct WaitTimeout: Error {}

/// Runs `work` and returns its result, or throws `WaitTimeout` if it is still running after `timeout`. Cancels the work
/// when the time is up, so an SDK wait that would otherwise run forever (such as `awaitRoomRemoteEcho`) can be bounded.
func withTimeout<T: Sendable>(
  _ timeout: Duration, _ work: @escaping @Sendable () async throws -> T
) async throws -> T {
  try await withThrowingTaskGroup(of: T.self) { group in
    group.addTask { try await work() }
    group.addTask {
      try await Task.sleep(for: timeout)
      throw WaitTimeout()
    }
    defer { group.cancelAll() }
    return try await group.next()!
  }
}
