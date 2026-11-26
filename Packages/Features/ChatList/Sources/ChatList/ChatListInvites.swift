import DesignSystem
import Domain
import SwiftUI

struct InvitesHeader: View {
  let invites: [RoomSummary]
  let isExpanded: Bool
  let viewModel: ChatListViewModel
  let toggle: () -> Void

  var body: some View {
    Button(action: toggle) {
      HStack(spacing: 12) {
        ZStack(alignment: .leading) {
          ForEach(Array(invites.prefix(3).enumerated()), id: \.element.id) { index, room in
            RoomAvatar(room: room, viewModel: viewModel, size: 32)
              .overlay(Circle().strokeBorder(SysColors.background, lineWidth: 2))
              .offset(x: CGFloat(index) * 14)
          }
        }
        .frame(width: 56, alignment: .leading)
        Text("Invitations")
          .textStyle(TextStyles.titleMedium.with(weight: .semibold))
          .foregroundStyle(SysColors.onSurface)
        Text("\(invites.count)")
          .textStyle(TextStyles.labelMedium)
          .foregroundStyle(SysColors.onPrimary)
          .padding(.horizontal, 7)
          .frame(minWidth: 22, minHeight: 22)
          .background(SysColors.primary, in: Capsule())
        Spacer(minLength: 8)
        Image(systemName: "chevron.right")
          .font(.system(size: 14, weight: .semibold))
          .foregroundStyle(SysColors.textSecondary)
          .rotationEffect(.degrees(isExpanded ? 90 : 0))
      }
      .padding(.horizontal, 16)
      .frame(height: 56)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel("\(invites.count) invitations")
    .accessibilityValue(isExpanded ? "Shown" : "Hidden")
  }
}

struct InviteRow: View {
  let room: RoomSummary
  let viewModel: ChatListViewModel

  var body: some View {
    let isAnswering = viewModel.answering.contains(room.id)
    HStack(spacing: 12) {
      RoomAvatar(room: room, viewModel: viewModel, size: 48)
      VStack(alignment: .leading, spacing: 2) {
        Text(room.name)
          .textStyle(TextStyles.titleMedium)
          .foregroundStyle(SysColors.onSurface)
          .lineLimit(1)
        Text("Invited you to chat")
          .textStyle(TextStyles.bodySmall)
          .foregroundStyle(SysColors.textSecondary)
          .lineLimit(1)
      }
      Spacer(minLength: 8)
      if isAnswering {
        ProgressView().frame(width: 80)
      } else {
        Button {
          Task { await viewModel.answerInvite(room, accept: false) }
        } label: {
          Image(systemName: "xmark")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(SysColors.onSurface)
            .frame(width: 34, height: 34)
            .background(SysColors.surface, in: Circle())
        }
        .accessibilityLabel("Decline \(room.name)")
        Button {
          Task { await viewModel.answerInvite(room, accept: true) }
        } label: {
          Image(systemName: "checkmark")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(SysColors.onPrimary)
            .frame(width: 34, height: 34)
            .background(SysColors.primary, in: Circle())
        }
        .accessibilityLabel("Accept \(room.name)")
      }
    }
    .buttonStyle(.plain)
    .padding(.horizontal, 16)
    .frame(height: 64)
  }
}

struct StackedLabelStyle: LabelStyle {
  func makeBody(configuration: Configuration) -> some View {
    VStack(spacing: 3) {
      configuration.icon.font(.system(size: 19))
      configuration.title.font(.caption2)
    }
    .frame(minWidth: 52)
  }
}
