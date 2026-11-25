import Domain

extension RoomKindBadge {
  var systemImage: String {
    switch self {
    case .space: "cube.fill"
    case .broadcast: "megaphone.fill"
    case .publicGroup: "globe"
    case .group: "person.2.fill"
    }
  }

  var accessibilityLabel: String {
    switch self {
    case .space: "Space"
    case .broadcast: "Broadcast"
    case .publicGroup: "Public group"
    case .group: "Group"
    }
  }
}
