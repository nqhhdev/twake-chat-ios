public enum RoomKindBadge: Sendable, Equatable, CaseIterable {
  case space, broadcast, publicGroup, group
}

extension RoomSummary {
  public var kindBadge: RoomKindBadge? {
    if isSpace { return .space }
    if isBroadcast { return .broadcast }
    if isDirect { return nil }
    return isPublic ? .publicGroup : .group
  }
}
