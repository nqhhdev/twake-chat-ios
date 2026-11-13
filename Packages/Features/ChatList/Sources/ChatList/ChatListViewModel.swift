import Domain
import Foundation
import Observation

/// The chat list: the joined rooms, as the repository orders them (most recent activity first), kept up to date, and
/// the Log out action. Logging out is the app's job: the coordinator passes it in, so this feature does not know the
/// authentication feature (ADR 0005).
@MainActor @Observable
public final class ChatListViewModel {
  public enum State: Equatable {
    case loading
    case loaded([RoomSummary])
    /// Signed in, but the room list has no joined room.
    case empty
    /// The room list could not be started.
    case failed(String)
  }

  public private(set) var state: State = .loading
  public private(set) var isLoggingOut = false
  /// Shown when logout failed and the session is still saved on this device.
  public private(set) var logOutErrorMessage: String?

  @ObservationIgnored private let repository: any RoomListRepository
  @ObservationIgnored private let logOutAction: @MainActor () async -> Bool
  /// Counts `start()` calls, so an earlier call whose stream a later one ended does not stop the later one.
  @ObservationIgnored private var startCount = 0

  /// - Parameter logOut: Signs out and returns `true`, or returns `false` when the session is still saved and the user
  ///   should try again.
  public init(repository: any RoomListRepository, logOut: @escaping @MainActor () async -> Bool) {
    self.repository = repository
    self.logOutAction = logOut
  }

  /// Starts the room list and follows its updates until the calling task is cancelled (the screen goes away) or the
  /// repository stops; the room list is then stopped, unless a later `start()` has begun meanwhile: starting again ends
  /// the earlier stream, and stopping then would end the later one too.
  public func start() async {
    startCount += 1
    let thisStart = startCount
    state = .loading
    let rooms: AsyncStream<[RoomSummary]>
    do {
      rooms = try await repository.start()
    } catch {
      if thisStart == startCount { state = .failed("Could not load your rooms.") }
      return
    }
    for await list in rooms where thisStart == startCount {
      state = list.isEmpty ? .empty : .loaded(list)
    }
    if thisStart == startCount { await repository.stop() }
  }

  public func logOut() async {
    guard !isLoggingOut else { return }
    isLoggingOut = true
    defer { isLoggingOut = false }
    logOutErrorMessage = nil
    if await !logOutAction() {
      logOutErrorMessage = "Could not log out. Please try again."
    }
  }

  /// The row's preview: "sender: text", or the text alone when the sender is unknown; `nil` without a text message.
  public static func preview(of room: RoomSummary) -> String? {
    guard let text = room.lastMessageText else { return nil }
    guard let sender = room.lastMessageSender else { return text }
    return "\(sender): \(text)"
  }
}
