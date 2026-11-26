import SwiftUI

enum RoomMetrics {
  static let gutter: CGFloat = 12
  static let barInset: CGFloat = 16
  static let avatarSize: CGFloat = 32
  static let avatarSpacing: CGFloat = 8
  static let avatarColumn: CGFloat = avatarSize + avatarSpacing
  static let bubbleInset: CGFloat = 12
  static let bubbleVerticalInset: CGFloat = 8
  static let capsuleInset: CGFloat = 12
  static let highlightBleed: CGFloat = 6
  static let skeletonDelay: Duration = .milliseconds(400)
  static let appendLimit = 3

  static func contentWidth(bubbleWidth: CGFloat, isOwn: Bool) -> CGFloat {
    max(0, bubbleWidth - 2 * bubbleInset - (isOwn ? 0 : avatarColumn))
  }

  static func reactionsWidth(bubbleWidth: CGFloat, isOwn: Bool) -> CGFloat {
    max(0, bubbleWidth - (isOwn ? 0 : avatarColumn))
  }

  static func animatesAppend(previousLastId: String?, rowIds: [String]) -> Bool {
    guard let previousLastId, let last = rowIds.last, last != previousLastId,
      let index = rowIds.lastIndex(of: previousLastId)
    else { return false }
    return rowIds.count - 1 - index <= appendLimit
  }
}
