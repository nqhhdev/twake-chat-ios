import DesignSystem
import Domain
import Foundation
import Observation
import SwiftUI

/// Emoji verification of this session (Flutter `key_verification`): this device asks the user's other devices, or
/// another device asks this one; both show the same emojis, and the user confirms they match. The app keeps one per
/// sign-in so a request from another device shows wherever the user is.
@MainActor @Observable
public final class VerificationViewModel: Identifiable {
  public private(set) var state: DeviceVerificationState = .unknown
  /// The step shown in the verification sheet; `nil` when none is under way.
  public private(set) var step: VerificationStep?
  public private(set) var errorMessage: String?
  /// A request from another device opened the sheet; it stays open through the steps until dismissed.
  public var isPresentingRequest = false

  @ObservationIgnored private let repository: any VerificationRepository

  public init(repository: any VerificationRepository) {
    self.repository = repository
  }

  nonisolated public var id: ObjectIdentifier { ObjectIdentifier(self) }

  /// Follows verification steps until the calling task ends; the app runs it once signed in.
  public func follow() async {
    state = await repository.state()
    for await next in await repository.steps() {
      withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { step = next }
      if case .incomingRequest = next { isPresentingRequest = true }
      if next == .verified { state = await repository.state() }
    }
  }

  public func refreshState() async {
    state = await repository.state()
  }

  /// Asks another of the user's devices to verify this one.
  public func start() async {
    errorMessage = nil
    step = .waitingForOtherDevice
    do {
      try await repository.requestVerification()
    } catch {
      step = nil
      errorMessage = "Could not start the verification. Please try again."
    }
  }

  public func accept() async {
    do { try await repository.acceptRequest() } catch { step = .failed }
  }

  public func confirm() async {
    do { try await repository.confirm() } catch { step = .failed }
  }

  public func decline() async {
    do { try await repository.decline() } catch { step = .failed }
  }

  /// Closes the sheet; a verification under way is cancelled.
  public func dismiss() async {
    if let step, ![.verified, .cancelled, .failed].contains(step) { await repository.cancel() }
    step = nil
    isPresentingRequest = false
  }
}

/// The verification sheet: waiting, the request, the emojis to compare, then done.
public struct VerificationSheet: View {
  let viewModel: VerificationViewModel
  @Environment(\.dismiss) private var dismissSheet

  public init(viewModel: VerificationViewModel) {
    self.viewModel = viewModel
  }

  public var body: some View {
    NavigationStack {
      VStack(spacing: 20) {
        content
      }
      .padding(24)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .navigationTitle("Verify this device")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(isFinished ? "Done" : "Cancel") {
            Task {
              await viewModel.dismiss()
              dismissSheet()
            }
          }
        }
      }
    }
    .presentationDetents([.medium, .large])
    .sensoryFeedback(.success, trigger: viewModel.step == .verified)
  }

  private var isFinished: Bool {
    [.verified, .cancelled, .failed].contains(viewModel.step)
  }

  @ViewBuilder private var content: some View {
    switch viewModel.step {
    case .waitingForOtherDevice, nil:
      ProgressView()
      Text(
        "Open Twake Chat on another device signed in to your account, and accept the request there."
      )
      .multilineTextAlignment(.center)
      .foregroundStyle(SysColors.textSecondary)
    case .incomingRequest(let deviceName):
      Image(systemName: "lock.shield").font(.system(size: 44)).foregroundStyle(SysColors.primary)
      Text("“\(deviceName)” wants to verify this device.").font(.headline).multilineTextAlignment(
        .center)
      HStack(spacing: 12) {
        Button("Decline", role: .cancel) { Task { await viewModel.dismiss() } }
          .buttonStyle(.bordered)
        Button("Accept") { Task { await viewModel.accept() } }
          .buttonStyle(.borderedProminent)
      }
    case .starting:
      ProgressView()
      Text("Getting the emojis…").foregroundStyle(SysColors.textSecondary)
    case .emojis(let emojis):
      Text("Check that the same emojis show, in the same order, on the other device.")
        .multilineTextAlignment(.center)
      LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 8)], spacing: 12) {
        ForEach(Array(emojis.enumerated()), id: \.offset) { _, emoji in
          VStack(spacing: 4) {
            Text(emoji.symbol).font(.system(size: 40))
            Text(emoji.name).font(.caption).foregroundStyle(SysColors.textSecondary)
          }
          .accessibilityElement(children: .combine)
        }
      }
      matchButtons
    case .numbers(let numbers):
      Text("Check that the same numbers show on the other device.").multilineTextAlignment(.center)
      Text(numbers.map(String.init).joined(separator: "  "))
        .font(.system(size: 34, weight: .semibold, design: .monospaced))
      matchButtons
    case .verified:
      Image(systemName: "checkmark.seal.fill").font(.system(size: 56)).foregroundStyle(
        SysColors.success)
      Text("This device is verified.").font(.headline)
    case .cancelled:
      Image(systemName: "xmark.circle").font(.system(size: 48)).foregroundStyle(
        SysColors.textSecondary)
      Text("The verification was cancelled.")
    case .failed:
      Image(systemName: "exclamationmark.triangle").font(.system(size: 48)).foregroundStyle(
        SysColors.error)
      Text("The verification did not finish. Please try again.").multilineTextAlignment(.center)
    }
  }

  private var matchButtons: some View {
    HStack(spacing: 12) {
      Button("They don’t match", role: .destructive) { Task { await viewModel.decline() } }
        .buttonStyle(.bordered)
      Button("They match") { Task { await viewModel.confirm() } }
        .buttonStyle(.borderedProminent)
    }
  }
}

/// The account's sessions (Flutter `device_settings`): this one first, then the others; a long press renames one.
@MainActor @Observable
public final class DevicesViewModel {
  public enum State: Equatable {
    case loading
    case loaded([DeviceSession])
    case failed(String)
  }

  public private(set) var state: State = .loading
  public private(set) var errorMessage: String?
  @ObservationIgnored private let repository: any DevicesRepository

  public init(repository: any DevicesRepository) {
    self.repository = repository
  }

  public func load() async {
    do {
      state = .loaded(try await repository.devices())
    } catch {
      state = .failed("Could not load your devices.")
    }
  }

  /// Renames a session; an empty name is ignored.
  public func rename(_ device: DeviceSession, to name: String) async {
    let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty else { return }
    errorMessage = nil
    do {
      try await repository.rename(deviceId: device.id, to: name)
      await load()
    } catch {
      errorMessage = "Could not rename the device."
    }
  }
}

struct DevicesScreen: View {
  let viewModel: DevicesViewModel
  @State private var renaming: DeviceSession?
  @State private var newName = ""

  var body: some View {
    Group {
      switch viewModel.state {
      case .loading:
        ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
      case .failed(let message):
        ContentUnavailableView(message, systemImage: "exclamationmark.triangle")
      case .loaded(let devices):
        List {
          ForEach(devices) { device in
            HStack(spacing: 12) {
              Image(systemName: icon(for: device))
                .font(.system(size: 22))
                .foregroundStyle(SysColors.primary)
                .frame(width: 32)
              VStack(alignment: .leading, spacing: 2) {
                Text(device.name).lineLimit(1)
                Text(detail(for: device))
                  .font(.footnote)
                  .foregroundStyle(SysColors.textSecondary)
              }
            }
            .contextMenu {
              Button("Rename", systemImage: "pencil") {
                newName = device.name
                renaming = device
              }
            }
            .swipeActions {
              Button("Rename") {
                newName = device.name
                renaming = device
              }
              .tint(SysColors.primary)
            }
          }
          if let message = viewModel.errorMessage {
            Text(message).foregroundStyle(SysColors.error)
          }
        }
        .refreshable { await viewModel.load() }
      }
    }
    .navigationTitle("Devices")
    .task { await viewModel.load() }
    .alert(
      "Rename device",
      isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })
    ) {
      TextField("Name", text: $newName)
      Button("Cancel", role: .cancel) {}
      Button("Save") {
        if let device = renaming { Task { await viewModel.rename(device, to: newName) } }
      }
    } message: {
      Text("Other people can see this name.")
    }
  }

  private func icon(for device: DeviceSession) -> String {
    if device.isCurrent { return "iphone" }
    let name = device.name.lowercased()
    if name.contains("iphone") || name.contains("ios") || name.contains("android") {
      return "iphone"
    }
    if name.contains("web") || name.contains("chrome") || name.contains("firefox") {
      return "globe"
    }
    return "desktopcomputer"
  }

  private func detail(for device: DeviceSession) -> String {
    if device.isCurrent { return "This device" }
    guard let lastSeen = device.lastSeen else { return device.id }
    return "Last seen \(lastSeen.formatted(.relative(presentation: .named)))"
  }
}
