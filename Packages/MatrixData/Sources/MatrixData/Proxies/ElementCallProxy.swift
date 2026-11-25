import Domain
import Foundation
import MatrixRustSDK

public actor ElementCallProxy: RoomCallRepository {
  private let clientProxy: @Sendable () async -> ClientProxy?
  private let discovery: ElementCallDiscovery
  private let fallbackURL: URL?
  private let clientId: String
  private var found: (userId: String, services: ElementCallDiscovery.Services)?

  public init(authentication: MatrixAuthenticationRepository, fallbackURL: URL?, clientId: String) {
    clientProxy = { await authentication.clientProxy }
    discovery = ElementCallDiscovery()
    self.fallbackURL = fallbackURL
    self.clientId = clientId
  }

  public func isAvailable() async -> Bool {
    guard let client = await clientProxy() else { return false }
    return await callURL(client) != nil
  }

  public func callStates(roomId: String) async -> AsyncStream<RoomCallState> {
    guard let client = await clientProxy(), let room = try? client.client.getRoom(roomId: roomId)
    else { return AsyncStream { $0.finish() } }
    let (stream, continuation) = AsyncStream<RoomCallState>.makeStream(
      bufferingPolicy: .bufferingNewest(1))
    continuation.yield(
      RoomCallState(
        isActive: room.hasActiveRoomCall(), participants: room.activeRoomCallParticipants()))
    let handle = room.subscribeToRoomInfoUpdates(
      listener: CallInfoListener { state in continuation.yield(state) })
    continuation.onTermination = { _ in handle.cancel() }
    return stream
  }

  public func open(roomId: String, intent: CallIntent) async throws(RoomCallError)
    -> any CallWidgetSession
  {
    guard let client = await clientProxy() else { throw .notJoined }
    guard let base = await callURL(client) else { throw .unavailable }
    guard let room = try? client.client.getRoom(roomId: roomId), room.membership() == .joined
    else { throw .notJoined }
    guard let userId = try? client.userId, let deviceId = try? client.deviceId else {
      throw .notJoined
    }
    let powerLevels = try? await room.getPowerLevels()
    if let powerLevels, !powerLevels.canOwnUserSendState(stateEvent: .callMember) {
      throw .notAllowed
    }
    let isDirect = await room.isDirect()
    let isEncrypted = await room.isEncrypted()
    let props = VirtualElementCallWidgetProperties(
      elementCallUrl: base.absoluteString, widgetId: UUID().uuidString, parentUrl: nil,
      fontScale: nil, font: nil, encryption: isEncrypted ? .perParticipantKeys : .unencrypted,
      posthogUserId: nil, posthogApiHost: nil, posthogApiKey: nil, rageshakeSubmitUrl: nil,
      sentryDsn: nil, sentryEnvironment: nil)
    let config = VirtualElementCallWidgetConfig(
      intent: Self.widgetIntent(intent, isDirect: isDirect), skipLobby: nil, header: .appBar,
      hideHeader: nil, preload: nil, appPrompt: false, confineToRoom: true,
      hideScreensharing: true, controlledAudioDevices: false,
      sendNotificationType: intent == .start ? .ring : nil)
    do {
      let settings = try newVirtualElementCallWidget(props: props, config: config)
      let urlText = try await generateWebviewUrl(
        widgetSettings: settings, room: room,
        props: ClientProperties(
          clientId: clientId, languageTag: Locale.preferredLanguages.first, theme: nil))
      guard let url = URL(string: urlText) else { throw RoomCallError.failed }
      let driver = try makeWidgetDriver(settings: settings)
      let capabilities = getElementCallRequiredPermissions(
        ownUserId: userId, ownDeviceId: deviceId)
      return ElementCallSession(
        url: url, userId: userId, room: room, driver: driver.driver, handle: driver.handle,
        capabilities: capabilities)
    } catch {
      throw .failed
    }
  }

  static func widgetIntent(_ intent: CallIntent, isDirect: Bool) -> Intent {
    switch (intent, isDirect) {
    case (.start, false): .startCall
    case (.join, false): .joinExisting
    case (.start, true): .startCallDm
    case (.join, true): .joinExistingDm
    }
  }

  private func callURL(_ client: ClientProxy) async -> URL? {
    guard let userId = try? client.userId else { return nil }
    let services: ElementCallDiscovery.Services
    if let found, found.userId == userId {
      services = found.services
    } else {
      guard let fresh = await discovery.services(forUserId: userId) else { return nil }
      found = (userId, fresh)
      services = fresh
    }
    guard services.livekitService != nil else { return nil }
    return services.widgetURL ?? fallbackURL
  }
}

final class ElementCallSession: CallWidgetSession {
  let url: URL
  let userId: String
  private let handle: WidgetDriverHandle
  private let running: Task<Void, Never>

  init(
    url: URL, userId: String, room: Room, driver: WidgetDriver, handle: WidgetDriverHandle,
    capabilities: WidgetCapabilities
  ) {
    self.url = url
    self.userId = userId
    self.handle = handle
    let provider = FixedCapabilities(capabilities: capabilities)
    running = Task { await driver.run(room: room, capabilitiesProvider: provider) }
  }

  func messagesToWidget() async -> AsyncStream<String> {
    let handle = handle
    return AsyncStream { continuation in
      let reading = Task {
        while !Task.isCancelled, let message = await handle.recv() {
          continuation.yield(message)
        }
        continuation.finish()
      }
      continuation.onTermination = { _ in reading.cancel() }
    }
  }

  func receiveFromWidget(_ message: String) async {
    _ = await handle.send(msg: message)
  }

  func end() async {
    running.cancel()
  }
}

private final class FixedCapabilities: WidgetCapabilitiesProvider {
  private let capabilities: WidgetCapabilities

  init(capabilities: WidgetCapabilities) {
    self.capabilities = capabilities
  }

  func acquireCapabilities(capabilities: WidgetCapabilities) -> WidgetCapabilities {
    self.capabilities
  }
}

private final class CallInfoListener: RoomInfoListener {
  private let onChange: @Sendable (RoomCallState) -> Void

  init(onChange: @escaping @Sendable (RoomCallState) -> Void) {
    self.onChange = onChange
  }

  func call(roomInfo: RoomInfo) {
    onChange(
      RoomCallState(
        isActive: roomInfo.hasRoomCall, participants: roomInfo.activeRoomCallParticipants))
  }
}
