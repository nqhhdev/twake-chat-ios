import Foundation
import Observation

@MainActor @Observable
public final class CallCenter {
  public static let shared = CallCenter()

  public private(set) var call: ActiveCall?
  public private(set) var roomId: String?
  public private(set) var isMinimized = false

  @ObservationIgnored private var system: (any CallSystemReporting)?

  public init() {}

  public func isInCall(roomId: String) -> Bool {
    call != nil && self.roomId == roomId
  }

  func start(_ call: ActiveCall, roomId: String, system: (any CallSystemReporting)?) async {
    await end()
    self.call = call
    self.roomId = roomId
    self.system = system
    isMinimized = false
    system?.onEndedBySystem = { [weak self] id in
      guard let self, self.call?.id == id else { return }
      Task { await self.end() }
    }
    await system?.reportStarted(call.id, title: call.title)
  }

  public func minimize() {
    guard call != nil else { return }
    isMinimized = true
  }

  public func restore() {
    isMinimized = false
  }

  public func fromWidget(_ message: String) async {
    guard let call else { return }
    if await call.fromWidget(message) {
      system?.reportConnected(call.id)
    }
    if call.hasEnded {
      await end()
    }
  }

  public func end() async {
    guard let call else { return }
    let system = self.system
    self.call = nil
    roomId = nil
    self.system = nil
    isMinimized = false
    call.markEnded()
    await call.session.end()
    await system?.reportEnded(call.id)
  }
}
