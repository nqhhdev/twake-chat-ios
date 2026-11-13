import Domain
import Foundation
import Testing

@testable import Settings

/// Emoji verification: asking another device, a request from another device, comparing, and the devices list.
@MainActor
struct VerificationViewModelTests {
  private actor FakeVerification: VerificationRepository {
    private var continuation: AsyncStream<VerificationStep>.Continuation?
    private(set) var calls: [String] = []
    var current: DeviceVerificationState = .unverified

    func state() async -> DeviceVerificationState { current }
    func steps() async -> AsyncStream<VerificationStep> {
      let (stream, continuation) = AsyncStream<VerificationStep>.makeStream()
      self.continuation = continuation
      return stream
    }
    var isFollowed: Bool { continuation != nil }
    func send(_ step: VerificationStep) {
      if step == .verified { current = .verified }
      continuation?.yield(step)
    }
    func finish() { continuation?.finish() }
    func requestVerification() async throws(VerificationError) { calls.append("request") }
    func acceptRequest() async throws(VerificationError) { calls.append("accept") }
    func confirm() async throws(VerificationError) { calls.append("confirm") }
    func decline() async throws(VerificationError) { calls.append("decline") }
    func cancel() async { calls.append("cancel") }
  }

  @Test func startingWaitsForTheOtherDeviceThenComparesAndVerifies() async {
    let fake = FakeVerification()
    let viewModel = VerificationViewModel(repository: fake)
    let following = Task { await viewModel.follow() }
    while await !fake.isFollowed { await Task.yield() }
    await viewModel.start()
    #expect(viewModel.step == .waitingForOtherDevice)
    let emojis = [VerificationEmoji(symbol: "🐶", name: "Dog")]
    await fake.send(.emojis(emojis))
    while viewModel.step != .emojis(emojis) { await Task.yield() }
    await viewModel.confirm()
    await fake.send(.verified)
    while viewModel.state != .verified { await Task.yield() }
    #expect(await fake.calls == ["request", "confirm"])
    await fake.finish()
    await following.value
  }

  @Test func aRequestFromAnotherDeviceOpensTheSheetUntilDismissed() async {
    let fake = FakeVerification()
    let viewModel = VerificationViewModel(repository: fake)
    let following = Task { await viewModel.follow() }
    while await !fake.isFollowed { await Task.yield() }
    await fake.send(.incomingRequest(deviceName: "Web"))
    while !viewModel.isPresentingRequest { await Task.yield() }
    await viewModel.accept()
    await fake.send(.starting)
    while viewModel.step != .starting { await Task.yield() }
    #expect(viewModel.isPresentingRequest)
    await viewModel.dismiss()
    #expect(!viewModel.isPresentingRequest)
    #expect(await fake.calls == ["accept", "cancel"])
    await fake.finish()
    await following.value
  }

  private struct FakeDevices: DevicesRepository {
    let renamed: @Sendable (String, String) -> Void
    func devices() async throws(DevicesError) -> [DeviceSession] {
      [DeviceSession(id: "ME", displayName: "iPhone", lastSeen: nil, isCurrent: true)]
    }
    func rename(deviceId: String, to name: String) async throws(DevicesError) {
      renamed(deviceId, name)
    }
  }

  @Test func devicesLoadAndRenameTrimsTheName() async {
    let renamed = Renamed()
    let viewModel = DevicesViewModel(repository: FakeDevices { renamed.set($0, $1) })
    await viewModel.load()
    guard case .loaded(let devices) = viewModel.state else {
      Issue.record("devices did not load")
      return
    }
    await viewModel.rename(devices[0], to: "  Work phone ")
    #expect(renamed.value == "ME Work phone")
  }

  private final class Renamed: @unchecked Sendable {
    private let lock = NSLock()
    private var stored = ""
    var value: String { lock.withLock { stored } }
    func set(_ id: String, _ name: String) { lock.withLock { stored = "\(id) \(name)" } }
  }
}
