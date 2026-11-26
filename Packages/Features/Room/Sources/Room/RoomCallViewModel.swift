import Domain
import Foundation
import Observation

@MainActor
public protocol CallSystemReporting: AnyObject {
  var onEndedBySystem: (@MainActor (UUID) -> Void)? { get set }
  func reportStarted(_ id: UUID, title: String) async
  func reportConnected(_ id: UUID)
  func reportEnded(_ id: UUID) async
}

enum CallWidgetAction {
  static let hangUpActions: Set<String> = ["im.vector.hangup", "io.element.close"]

  static func isHangUp(_ message: String) -> Bool {
    guard let object = parse(message), object["api"] as? String == "fromWidget",
      let action = object["action"] as? String
    else { return false }
    return hangUpActions.contains(action)
  }

  static func isJoined(_ message: String) -> Bool {
    guard let object = parse(message), object["api"] as? String == "fromWidget" else {
      return false
    }
    return object["action"] as? String == "io.element.join"
  }

  private static func parse(_ message: String) -> [String: Any]? {
    (try? JSONSerialization.jsonObject(with: Data(message.utf8))) as? [String: Any]
  }
}

@MainActor @Observable
public final class ActiveCall: Identifiable {
  public let id = UUID()
  public let title: String
  public private(set) var hasEnded = false
  @ObservationIgnored let session: any CallWidgetSession

  init(session: any CallWidgetSession, title: String) {
    self.session = session
    self.title = title
  }

  public var url: URL { session.url }

  func fromWidget(_ message: String) async -> Bool {
    await session.receiveFromWidget(message)
    if CallWidgetAction.isHangUp(message) {
      hasEnded = true
    }
    return CallWidgetAction.isJoined(message)
  }

  func markEnded() { hasEnded = true }
}

@MainActor @Observable
public final class RoomCallViewModel {
  public let roomId: String
  public private(set) var isAvailable = false
  public private(set) var state = RoomCallState.idle
  public private(set) var isOpening = false
  public var errorMessage: String?

  @ObservationIgnored private let repository: any RoomCallRepository
  @ObservationIgnored private let system: (any CallSystemReporting)?
  @ObservationIgnored let center: CallCenter

  public init(
    roomId: String, repository: any RoomCallRepository,
    system: (any CallSystemReporting)? = nil, center: CallCenter = .shared
  ) {
    self.roomId = roomId
    self.repository = repository
    self.system = system
    self.center = center
  }

  public var activeCall: ActiveCall? {
    center.isInCall(roomId: roomId) ? center.call : nil
  }

  public var participantCount: Int { state.participants.count }

  public var actionTitle: String {
    state.isActive ? localized("Join call") : localized("Start call")
  }

  public func load() async {
    isAvailable = await repository.isAvailable()
  }

  public func joinIfAnswered(title: String) async {
    guard isAvailable, center.takePendingJoin(roomId: roomId) else { return }
    await open(title: title, joining: true)
  }

  public func watch() async {
    for await next in await repository.callStates(roomId: roomId) {
      state = next
    }
  }

  public func open(title: String, joining: Bool = false) async {
    if activeCall != nil {
      center.restore()
      return
    }
    guard isAvailable, !isOpening else { return }
    isOpening = true
    defer { isOpening = false }
    errorMessage = nil
    do {
      let session = try await repository.open(
        roomId: roomId, intent: joining || state.isActive ? .join : .start)
      await center.start(
        ActiveCall(session: session, title: title), roomId: roomId, system: system)
    } catch RoomCallError.notAllowed {
      errorMessage = localized("You may not join a call in this chat.")
    } catch RoomCallError.notJoined {
      errorMessage = localized("You are no longer in this chat.")
    } catch {
      errorMessage = localized("The call could not be started. Please try again.")
    }
  }

  public func fromWidget(_ message: String) async {
    guard activeCall != nil else { return }
    await center.fromWidget(message)
  }

  public func close() async {
    guard activeCall != nil else { return }
    await center.end()
  }
}
