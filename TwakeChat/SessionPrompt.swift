import DesignSystem
import Domain
import Observation
import SwiftUI

@MainActor @Observable
final class SessionPrompt {
  static let pauses: [Duration] = [.seconds(3), .seconds(10)]

  private(set) var warning: SessionWarning?
  @ObservationIgnored private var isDismissed = false
  @ObservationIgnored private let sleep: @Sendable (Duration) async -> Void

  init(sleep: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) }) {
    self.sleep = sleep
  }

  func start(checking check: (@Sendable () async -> SessionWarning?)?) async {
    guard let check else { return }
    for pause in Self.pauses {
      await sleep(pause)
      if Task.isCancelled || isDismissed { return }
      if let found = await check() {
        if !isDismissed { warning = found }
        return
      }
    }
  }

  func dismiss() {
    isDismissed = true
    warning = nil
  }

  func refresh(checking check: (@Sendable () async -> SessionWarning?)?) async {
    guard warning != nil, let check else { return }
    warning = await check()
  }
}

struct SessionPromptBanner: View {
  let warning: SessionWarning
  let onFix: () -> Void
  let onLater: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .top, spacing: 12) {
        Image(systemName: "exclamationmark.shield.fill")
          .font(.title3)
          .foregroundStyle(SysColors.warning)
          .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 2) {
          Text("Unlock your encrypted messages")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(SysColors.onSurface)
          Text(message)
            .font(.subheadline)
            .foregroundStyle(SysColors.onSurfaceVariant)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      HStack(spacing: 8) {
        Spacer(minLength: 0)
        Button("Later", action: onLater)
          .buttonStyle(.borderless)
          .controlSize(.small)
        Button(action: onFix) {
          Text(warning == .unverified ? "Verify this device" : "Enter recovery key")
            .font(.subheadline.weight(.semibold))
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .controlSize(.small)
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.bar)
    .overlay(alignment: .bottom) { Rectangle().fill(SysColors.surface).frame(height: 1) }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier(A11yIdentifiers.chatList.sessionPrompt)
  }

  private var message: String {
    switch warning {
    case .unverified:
      "Verify this device with another one, or with your recovery key, to read your encrypted messages."
    case .recoveryIncomplete:
      "Enter your recovery key to read the encrypted messages sent before you signed in here."
    }
  }
}
