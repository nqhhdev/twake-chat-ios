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
  public var activeCall: ActiveCall?

  @ObservationIgnored private let repository: any RoomCallRepository
  @ObservationIgnored private let system: (any CallSystemReporting)?

  public init(
    roomId: String, repository: any RoomCallRepository,
    system: (any CallSystemReporting)? = nil
  ) {
    self.roomId = roomId
    self.repository = repository
    self.system = system
  }

  public var participantCount: Int { state.participants.count }

  public var actionTitle: String { state.isActive ? "Join call" : "Start call" }

  public func load() async {
    isAvailable = await repository.isAvailable()
  }

  public func watch() async {
    for await next in await repository.callStates(roomId: roomId) {
      state = next
    }
  }

  public func open(title: String) async {
    guard isAvailable, !isOpening, activeCall == nil else { return }
    isOpening = true
    defer { isOpening = false }
    errorMessage = nil
    do {
      let session = try await repository.open(
        roomId: roomId, intent: state.isActive ? .join : .start)
      let call = ActiveCall(session: session, title: title)
      activeCall = call
      system?.onEndedBySystem = { [weak self] id in
        guard let self, self.activeCall?.id == id else { return }
        Task { await self.close() }
      }
      await system?.reportStarted(call.id, title: title)
    } catch RoomCallError.notAllowed {
      errorMessage = "You may not join a call in this chat."
    } catch RoomCallError.notJoined {
      errorMessage = "You are no longer in this chat."
    } catch {
      errorMessage = "The call could not be started. Please try again."
    }
  }

  public func fromWidget(_ message: String) async {
    guard let call = activeCall else { return }
    if await call.fromWidget(message) {
      system?.reportConnected(call.id)
    }
    if call.hasEnded {
      await close()
    }
  }

  public func close() async {
    guard let call = activeCall else { return }
    activeCall = nil
    call.markEnded()
    await call.session.end()
    await system?.reportEnded(call.id)
  }
}
