import AVFoundation
import CallKit
import Foundation

@MainActor
public final class CallKitReporter: NSObject, CallSystemReporting {
  public static let shared = CallKitReporter()

  public var onEndedBySystem: (@MainActor (UUID) -> Void)?
  private let provider: CXProvider
  private let controller = CXCallController()
  private var endingFromApp: Set<UUID> = []

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

  public func reportStarted(_ id: UUID, title: String) async {
    let action = CXStartCallAction(call: id, handle: CXHandle(type: .generic, value: title))
    action.isVideo = true
    action.contactIdentifier = title
    try? await controller.request(CXTransaction(action: action))
    provider.reportOutgoingCall(with: id, startedConnectingAt: Date())
  }

  public func reportConnected(_ id: UUID) {
    provider.reportOutgoingCall(with: id, connectedAt: Date())
  }

  public func reportEnded(_ id: UUID) async {
    endingFromApp.insert(id)
    do {
      try await controller.request(CXTransaction(action: CXEndCallAction(call: id)))
    } catch {
      endingFromApp.remove(id)
      provider.reportCall(with: id, endedAt: Date(), reason: .remoteEnded)
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
    if endingFromApp.remove(id) == nil {
      onEndedBySystem?(id)
    }
  }
}

extension CallKitReporter: CXProviderDelegate {
  nonisolated public func providerDidReset(_ provider: CXProvider) {}

  nonisolated public func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
    MainActor.assumeIsolated { Self.activateAudio() }
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
