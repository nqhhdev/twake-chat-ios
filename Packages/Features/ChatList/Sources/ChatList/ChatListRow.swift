import DesignSystem
import Domain
import SwiftUI

struct ChatListRow: View {
  let room: RoomSummary
  let viewModel: ChatListViewModel

  var body: some View {
    let spaceUnread = viewModel.spaceUnread(of: room)
    let isUnread = spaceUnread.map { $0.badgeCount > 0 } ?? room.isUnread
    HStack(alignment: .top, spacing: 12) {
      RoomAvatar(room: room, viewModel: viewModel, size: 52)
        .overlay(alignment: .bottomTrailing) {
          if let dot = viewModel.presenceDot(of: room) {
            AvatarPresenceDot(AvatarPresence(dot), avatarSize: 52).offset(x: 2, y: 2)
          } else if let kind = room.kindBadge {
            AvatarKindBadge(
              systemImage: kind.systemImage, label: kind.accessibilityLabel, avatarSize: 52
            )
            .offset(x: 3, y: 3)
          }
        }
        .task(id: room.directUserId) { await viewModel.refreshPresence(of: room) }
      VStack(alignment: .leading, spacing: 2) {
        HStack(alignment: .firstTextBaseline) {
          Text(room.name)
            .font(.headline.weight(isUnread ? .bold : .semibold))
            .foregroundStyle(SysColors.onSurface)
            .lineLimit(1)
          if room.isEncrypted {
            Image(systemName: "lock.fill").font(.caption2).foregroundStyle(SysColors.textSecondary)
              .accessibilityLabel(localized("Encrypted"))
          }
          if room.isFavourite {
            Image(systemName: "star.fill").font(.caption2).foregroundStyle(.orange)
          }
          if room.isMuted {
            Image(systemName: "bell.slash.fill").font(.caption2).foregroundStyle(
              SysColors.textSecondary
            )
            .accessibilityLabel(localized("Muted"))
          }
          Spacer(minLength: 4)
          if let date = room.lastActivity {
            Text(ChatListViewModel.timeText(date))
              .font(.subheadline)
              .foregroundStyle(isUnread ? SysColors.primary : SysColors.textSecondary)
          }
        }
        HStack(alignment: .top) {
          Group {
            if let typing = ChatListViewModel.typingLine(of: room) {
              Text(typing).foregroundStyle(SysColors.primary)
            } else if let draft = room.draft, !room.isSpace {
              Text(
                "\(Text(localized("Draft:")).foregroundStyle(SysColors.error)) \(draft)"
              )
              .foregroundStyle(SysColors.textSecondary)
            } else if !room.isSpace, let state = room.lastMessageSendState,
              let preview = ChatListViewModel.preview(of: room)
            {
              Text("\(SendStateMark(state: state).image) \(preview)")
                .foregroundStyle(SysColors.textSecondary)
            } else {
              Text(room.isSpace ? localized("Space") : ChatListViewModel.preview(of: room) ?? " ")
                .foregroundStyle(SysColors.textSecondary)
            }
          }
          .font(.subheadline)
          .lineLimit(2, reservesSpace: true)
          .contentTransition(.opacity)
          .animation(.easeInOut(duration: 0.25), value: room.draft)
          Spacer(minLength: 4)
          if let spaceUnread {
            UnreadBadge(
              unread: spaceUnread.badgeCount, mentions: spaceUnread.mentions,
              isMuted: room.isMuted || spaceUnread.isQuiet)
          } else {
            UnreadBadge(
              unread: room.unreadCount, mentions: room.mentionCount, isMuted: room.isMuted,
              isMarkedUnread: room.isMarkedUnread)
          }
        }
      }
      .alignmentGuide(.listRowSeparatorLeading) { dimensions in dimensions[.leading] }
    }
    .padding(.vertical, 10)
    .contentShape(Rectangle())
  }
}

struct UnreadBadge: View {
  let unread: Int
  let mentions: Int
  var isMuted = false
  var isMarkedUnread = false

  private var fill: ColorToken { isMuted ? SysColors.textSecondary : SysColors.primary }

  var body: some View {
    HStack(spacing: 4) {
      if mentions > 0 {
        Text(verbatim: "@")
          .textStyle(TextStyles.labelMedium)
          .foregroundStyle(SysColors.onPrimary)
          .frame(width: 20, height: 20)
          .background(fill, in: Circle())
          .transition(.scale.combined(with: .opacity))
      }
      if unread > 0 {
        Text(verbatim: unread > 999 ? "999+" : "\(unread)")
          .textStyle(TextStyles.labelMedium)
          .foregroundStyle(SysColors.onPrimary)
          .contentTransition(.numericText(value: Double(unread)))
          .padding(.horizontal, 6)
          .frame(minWidth: 20, minHeight: 20)
          .background(fill, in: Capsule())
          .transition(.scale.combined(with: .opacity))
      } else if isMarkedUnread, mentions == 0 {
        Circle().fill(fill).frame(width: 12, height: 12)
          .accessibilityLabel(localized("Marked as unread"))
          .transition(.scale.combined(with: .opacity))
      }
    }
    .animation(.spring(response: 0.3, dampingFraction: 0.6), value: unread)
    .animation(.spring(response: 0.3, dampingFraction: 0.6), value: mentions)
  }
}

struct SendStateMark {
  let state: RoomSummary.SendState

  var image: Text {
    switch state {
    case .sending: Text(Image(systemName: "clock")).accessibilityLabel(localized("Sending"))
    case .sent: Text(Image(systemName: "checkmark")).accessibilityLabel(localized("Sent"))
    case .failed:
      Text(Image(systemName: "exclamationmark.circle.fill")).foregroundStyle(SysColors.error)
        .accessibilityLabel(localized("Not sent"))
    }
  }
}

struct RoomAvatar: View {
  let room: RoomSummary
  let viewModel: ChatListViewModel
  var size: CGFloat = 56

  var body: some View {
    let reference = room.avatar
    TwakeAvatar(
      name: room.name, size: size, pictureID: reference?.source,
      load: reference.map { reference in
        { @Sendable [viewModel] in await viewModel.picture(reference) }
      })
  }
}
