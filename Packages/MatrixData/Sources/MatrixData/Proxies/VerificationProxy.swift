import Domain
import Foundation
import MatrixRustSDK

/// `VerificationRepository` on the SDK's session verification controller (ADR 0006): its delegate's callbacks become
/// `VerificationStep`s. The controller is made once per signed-in client and kept, so a request from another device
/// reaches the app while it runs. Nothing here logs.
public actor VerificationProxy: VerificationRepository {
  private let clientProxy: @Sendable () async -> ClientProxy?
  private var controller: SessionVerificationController?
  private var delegate: Delegate?
  private var continuation: AsyncStream<VerificationStep>.Continuation?

  public init(authentication: MatrixAuthenticationRepository) {
    clientProxy = { await authentication.clientProxy }
  }

  public func state() async -> DeviceVerificationState {
    guard let client = await clientProxy() else { return .unknown }
    switch client.client.encryption().verificationState() {
    case .verified: return .verified
    case .unverified: return .unverified
    case .unknown: return .unknown
    }
  }

  public func steps() async -> AsyncStream<VerificationStep> {
    let (stream, continuation) = AsyncStream<VerificationStep>.makeStream(
      bufferingPolicy: .bufferingNewest(4))
    self.continuation?.finish()
    self.continuation = continuation
    _ = try? await activeController()
    return stream
  }

  public func requestVerification() async throws(VerificationError) {
    let controller = try await activeController()
    do {
      try await controller.requestDeviceVerification()
      continuation?.yield(.waitingForOtherDevice)
    } catch {
      throw .requestFailed
    }
  }

  public func acceptRequest() async throws(VerificationError) {
    let controller = try await activeController()
    do {
      try await controller.acceptVerificationRequest()
      continuation?.yield(.starting)
    } catch {
      throw .requestFailed
    }
  }

  public func confirm() async throws(VerificationError) {
    let controller = try await activeController()
    do { try await controller.approveVerification() } catch { throw .requestFailed }
  }

  public func decline() async throws(VerificationError) {
    let controller = try await activeController()
    do { try await controller.declineVerification() } catch { throw .requestFailed }
  }

  public func cancel() async {
    try? await controller?.cancelVerification()
  }

  /// The controller, made once with its delegate.
  private func activeController() async throws(VerificationError) -> SessionVerificationController {
    if let controller { return controller }
    guard let client = await clientProxy() else { throw .notSignedIn }
    guard let made = try? await client.client.getSessionVerificationController() else {
      throw .requestFailed
    }
    let delegate = Delegate { [weak self] step in
      Task { await self?.publish(step) }
    } acknowledge: { [weak made] senderId, flowId in
      Task { try? await made?.acknowledgeVerificationRequest(senderId: senderId, flowId: flowId) }
    }
    made.setDelegate(delegate: delegate)
    controller = made
    self.delegate = delegate
    return made
  }

  private func publish(_ step: VerificationStep) {
    continuation?.yield(step)
  }

  /// The SDK's callbacks, on its own threads.
  private final class Delegate: SessionVerificationControllerDelegate, @unchecked Sendable {
    private let send: @Sendable (VerificationStep) -> Void
    private let acknowledge: @Sendable (String, String) -> Void

    init(
      _ send: @escaping @Sendable (VerificationStep) -> Void,
      acknowledge: @escaping @Sendable (String, String) -> Void
    ) {
      self.send = send
      self.acknowledge = acknowledge
    }

    func didReceiveVerificationRequest(details: SessionVerificationRequestDetails) {
      acknowledge(details.senderProfile.userId, details.flowId)
      send(.incomingRequest(deviceName: details.deviceDisplayName ?? details.deviceId))
    }

    func didAcceptVerificationRequest() { send(.starting) }
    func didStartSasVerification() { send(.starting) }

    func didReceiveVerificationData(data: SessionVerificationData) {
      switch data {
      case .emojis(let emojis, _):
        send(.emojis(emojis.map { VerificationEmoji(symbol: $0.symbol(), name: $0.description()) }))
      case .decimals(let values):
        send(.numbers(values.map(Int.init)))
      }
    }

    func didFail() { send(.failed) }
    func didCancel() { send(.cancelled) }
    func didFinish() { send(.verified) }
  }
}
