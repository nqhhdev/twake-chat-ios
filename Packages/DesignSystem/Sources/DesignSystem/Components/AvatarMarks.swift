import SwiftUI

public enum AvatarPresence: Sendable, Equatable {
  case online, away
}

public struct AvatarPresenceDot: View {
  private let presence: AvatarPresence
  private let avatarSize: CGFloat

  public init(_ presence: AvatarPresence, avatarSize: CGFloat) {
    self.presence = presence
    self.avatarSize = avatarSize
  }

  public var body: some View {
    let diameter: CGFloat = avatarSize > 40 ? 12 : 10
    Circle()
      .fill(presence == .online ? SysColors.success : SysColors.warning)
      .frame(width: diameter, height: diameter)
      .padding(2)
      .background(SysColors.background, in: Circle())
      .accessibilityElement()
      .accessibilityLabel(presence == .online ? "Online" : "Away")
  }
}

public struct AvatarKindBadge: View {
  private let systemImage: String
  private let label: String
  private let avatarSize: CGFloat

  public init(systemImage: String, label: String, avatarSize: CGFloat) {
    self.systemImage = systemImage
    self.label = label
    self.avatarSize = avatarSize
  }

  public var body: some View {
    let diameter = max(14, (avatarSize * 0.36).rounded())
    Image(systemName: systemImage)
      .font(.system(size: diameter * 0.55, weight: .semibold))
      .foregroundStyle(SysColors.onSecondaryContainer)
      .frame(width: diameter, height: diameter)
      .background(SysColors.secondaryContainer, in: Circle())
      .padding(2)
      .background(SysColors.background, in: Circle())
      .accessibilityElement()
      .accessibilityLabel(label)
  }
}

#Preview("Avatar marks") {
  HStack(spacing: 16) {
    TwakeAvatar(name: "Alice", size: 52)
      .overlay(alignment: .bottomTrailing) { AvatarPresenceDot(.online, avatarSize: 52) }
    TwakeAvatar(name: "Bob", size: 52)
      .overlay(alignment: .bottomTrailing) { AvatarPresenceDot(.away, avatarSize: 52) }
    TwakeAvatar(name: "Team", size: 52)
      .overlay(alignment: .bottomTrailing) {
        AvatarKindBadge(systemImage: "person.2.fill", label: "Group", avatarSize: 52)
      }
  }
  .padding()
}
