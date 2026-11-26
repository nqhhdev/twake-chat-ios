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
    case .space: localized("Space")
    case .broadcast: localized("Broadcast")
    case .publicGroup: localized("Public group")
    case .group: localized("Group")
    }
  }
}
