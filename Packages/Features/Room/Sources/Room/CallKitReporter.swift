import AVFoundation
import CallKit
import Domain
import Foundation

@MainActor
public final class CallKitReporter: NSObject, CallSystemReporting {
  public static let shared = CallKitReporter()

  public var onEndedBySystem: (@MainActor (UUID) -> Void)?
  public var onAnswer: (@MainActor (CallRing) -> Void)?
  public var onDecline: (@MainActor (CallRing) -> Void)?
  private let provider: CXProvider
  private let controller = CXCallController()
  private var endingFromApp: Set<UUID> = []
  private var incoming: [UUID: CallRing] = [:]
  private var identities = CallIdentities()

  override private init() {
    let configuration = CXProviderConfiguration()
    configuration.supportsVideo = true
    configuration.maximumCallGroups = 1
    configuration.maximumCallsPerCallGroup = 1
    configuration.supportedHandleTypes = [.generic]
    configuration.includesCallsInRecents = false
    provider = CXProvider(configuration: configuration)
    super.init()
    provider.setDelegate(self, queue: nil)
  }

  @discardableResult
  public func reportIncoming(_ ring: CallRing) async -> Bool {
    guard !incoming.values.contains(where: { $0.eventId == ring.eventId }) else { return false }
    let id = UUID()
    let update = CXCallUpdate()
    update.remoteHandle = CXHandle(type: .generic, value: ring.roomName)
    update.localizedCallerName = ring.roomName
    update.hasVideo = !ring.isVoice
    update.supportsHolding = false
    update.supportsGrouping = false
    update.supportsUngrouping = false
    update.supportsDTMF = false
    do {
      try await provider.reportNewIncomingCall(with: id, update: update)
    } catch {
      return false
    }
    incoming[id] = ring
    let wait = max(0, ring.expiresAt.timeIntervalSinceNow)
    Task { [weak self] in
      try? await Task.sleep(for: .seconds(wait))
      self?.stopRinging(id)
    }
    return true
  }

  public func reportUnusable() async {
    let id = UUID()
    try? await provider.reportNewIncomingCall(with: id, update: CXCallUpdate())
    provider.reportCall(with: id, endedAt: Date(), reason: .failed)
  }

  public func endPendingAnswer() {
    guard let id = identities.takeAnswer() else { return }
    provider.reportCall(with: id, endedAt: Date(), reason: .failed)
  }

  private func stopRinging(_ id: UUID) {
    guard incoming.removeValue(forKey: id) != nil else { return }
    provider.reportCall(with: id, endedAt: Date(), reason: .unanswered)
  }

  public func reportStarted(_ id: UUID, title: String) async {
    if identities.start(id) != nil { return }
    let action = CXStartCallAction(call: id, handle: CXHandle(type: .generic, value: title))
    action.isVideo = true
    action.contactIdentifier = title
    try? await controller.request(CXTransaction(action: action))
    provider.reportOutgoingCall(with: id, startedConnectingAt: Date())
  }

  public func reportConnected(_ id: UUID) {
    guard !identities.isAnswered(id) else { return }
    provider.reportOutgoingCall(with: id, connectedAt: Date())
  }

  public func reportEnded(_ id: UUID) async {
    let systemId = identities.systemId(for: id)
    identities.end(id)
    endingFromApp.insert(systemId)
    do {
      try await controller.request(CXTransaction(action: CXEndCallAction(call: systemId)))
    } catch {
      endingFromApp.remove(systemId)
      provider.reportCall(with: systemId, endedAt: Date(), reason: .remoteEnded)
    }
    Self.deactivateAudio()
  }

  static func activateAudio() {
    let session = AVAudioSession.sharedInstance()
    try? session.setCategory(
      .playAndRecord, mode: .videoChat,
      options: [.allowBluetoothA2DP, .defaultToSpeaker])
    try? session.setActive(true)
  }

  static func deactivateAudio() {
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
  }

  fileprivate func endedBySystem(_ id: UUID) {
    if let ring = incoming.removeValue(forKey: id) {
      identities.dropAnswer(id)
      onDecline?(ring)
      return
    }
    if endingFromApp.remove(id) == nil {
      onEndedBySystem?(identities.appId(for: id))
    }
  }

  fileprivate func answered(_ id: UUID) {
    guard let ring = incoming.removeValue(forKey: id) else { return }
    identities.answer(id)
    onAnswer?(ring)
  }
}

extension CallKitReporter: CXProviderDelegate {
  nonisolated public func providerDidReset(_ provider: CXProvider) {}

  nonisolated public func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
    MainActor.assumeIsolated { Self.activateAudio() }
    action.fulfill()
  }

  nonisolated public func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
    let id = action.callUUID
    MainActor.assumeIsolated {
      Self.activateAudio()
      answered(id)
    }
    action.fulfill()
  }

  nonisolated public func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
    let id = action.callUUID
    action.fulfill()
    MainActor.assumeIsolated { endedBySystem(id) }
  }

  nonisolated public func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) {
    action.fail()
  }

  nonisolated public func provider(_ provider: CXProvider, perform action: CXSetHeldCallAction) {
    action.fail()
  }
}
