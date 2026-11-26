import DesignSystem
import Domain
import SwiftUI

/// In place of the composer once the room was upgraded (`m.room.tombstone`, Flutter `ChatUpgradeBanner`): the
/// conversation goes on in the new room, which the button opens.
struct SuccessorRoomBar: View {
  let link: URL
  @Environment(\.openURL) private var openURL

  var body: some View {
    VStack(spacing: 8) {
      Label(
        localized("This chat has been replaced and is no longer active."),
        systemImage: "arrow.up.forward.square"
      )
      .font(.subheadline)
      .foregroundStyle(SysColors.textSecondary)
      .multilineTextAlignment(.center)
      Button(localized("Go to the new chat")) { openURL(link) }
        .buttonStyle(.borderedProminent)
    }
    .frame(maxWidth: .infinity)
    .padding(12)
    .background(.bar)
  }
}

/// In place of the composer in a direct chat with someone the user blocked (Flutter `BlockedUserBanner`).
struct BlockedPersonBar: View {
  let viewModel: RoomViewModel
  @State private var isWorking = false

  var body: some View {
    VStack(spacing: 8) {
      Label(localized("You blocked this person."), systemImage: "hand.raised")
        .font(.subheadline)
        .foregroundStyle(SysColors.textSecondary)
      Button {
        isWorking = true
        Task {
          await viewModel.unblock()
          isWorking = false
        }
      } label: {
        Group { if isWorking { ProgressView() } else { Text(localized("Unblock")) } }
          .frame(maxWidth: 280)
      }
      .buttonStyle(.bordered)
      .disabled(isWorking)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 12)
    .background(.bar)
  }
}

/// Above the timeline when a member's identity changed (Element X `IdentityPinningViolation`): their messages may
/// not be from them until the user accepts the new identity, or checks with them first.
struct IdentityWarningBanner: View {
  let warning: IdentityWarning
  let onAccept: () -> Void
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: "exclamationmark.shield.fill")
        .font(.title3)
        .foregroundStyle(
          warning.kind == .verifiedChanged
            ? AnyShapeStyle(SysColors.error) : AnyShapeStyle(Color.orange)
        )
        .symbolEffect(.pulse, options: .repeat(2), isActive: !reduceMotion)
      VStack(alignment: .leading, spacing: 6) {
        Text(
          warning.kind == .verifiedChanged
            ? localized("\(warning.name)'s verified identity was reset.")
            : localized("\(warning.name)'s identity was reset.")
        )
        .font(.subheadline.weight(.semibold))
        Text(localized("Check with them another way before trusting new messages."))
          .font(.footnote)
          .foregroundStyle(SysColors.textSecondary)
        Button(
          warning.kind == .verifiedChanged
            ? localized("Withdraw verification") : localized("OK, I understand")
        ) {
          onAccept()
        }
        .font(.footnote.weight(.semibold))
        .buttonStyle(.bordered)
        .controlSize(.small)
      }
      Spacer(minLength: 0)
    }
    .padding(12)
    .background(.bar)
    .accessibilityElement(children: .contain)
  }
}

/// In place of the composer in a chat the user left: why it is read-only, and Rejoin.
struct ArchivedRoomBar: View {
  let viewModel: RoomViewModel

  var body: some View {
    VStack(spacing: 8) {
      Text(localized("You left this chat."))
        .font(.subheadline)
        .foregroundStyle(SysColors.textSecondary)
      Button {
        Task { await viewModel.rejoin() }
      } label: {
        Group {
          if viewModel.isRejoining { ProgressView() } else { Text(localized("Rejoin")) }
        }
        .frame(maxWidth: 280)
      }
      .buttonStyle(.borderedProminent)
      .disabled(viewModel.isRejoining)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 12)
    .background(.bar)
  }
}

/// Above the timeline when encrypted messages may not show on this device (Flutter `ChatDeviceVerificationBanner`): why,
/// and the button that opens Privacy & Security to verify the device or enter the recovery key. It stays until that is
/// done, as on the Flutter app's phone layout.
struct SessionWarningBanner: View {
  let warning: SessionWarning
  let onFix: () -> Void

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: "exclamationmark.shield.fill")
        .font(.title3)
        .foregroundStyle(SysColors.warning)
        .accessibilityHidden(true)
      Text(message)
        .font(.subheadline)
        .foregroundStyle(SysColors.onSurface)
        .fixedSize(horizontal: false, vertical: true)
      Spacer(minLength: 4)
      Button(action: onFix) {
        Text(warning == .unverified ? localized("Verify") : localized("Enter Key")).font(
          .subheadline.weight(.semibold))
      }
      .buttonStyle(.bordered)
      .buttonBorderShape(.capsule)
      .controlSize(.small)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
    .frame(maxWidth: .infinity)
    .background(.bar)
    .overlay(alignment: .bottom) { Rectangle().fill(SysColors.surface).frame(height: 1) }
  }

  private var message: String {
    switch warning {
    case .unverified: localized("Encrypted messages may not show until this device is verified.")
    case .recoveryIncomplete:
      localized("Encrypted messages may not show until you enter your recovery key.")
    }
  }
}
