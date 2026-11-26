import DesignSystem
import SwiftUI

/// Grey bubbles that stand in for the messages while the chat loads, as the Flutter app's `ChatLoadingView` does:
/// others' bubbles on the left with an avatar, one's own on the right, stacked from the bottom. Each row keeps a fixed
/// size so the shapes do not jump when the view redraws; they pulse gently unless Reduce Motion is on.
struct TimelineSkeleton: View {
  let bubbleWidth: CGFloat

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var isDimmed = false
  @State private var isShown = false

  /// One stand-in message: whether it is one's own, its share of `bubbleWidth`, and its height.
  private struct Row {
    let isOwn: Bool
    let widthRatio: CGFloat
    let height: CGFloat
  }

  private static let rows: [Row] = [
    Row(isOwn: false, widthRatio: 0.55, height: 40),
    Row(isOwn: false, widthRatio: 0.8, height: 64),
    Row(isOwn: true, widthRatio: 0.5, height: 40),
    Row(isOwn: false, widthRatio: 0.65, height: 52),
    Row(isOwn: true, widthRatio: 0.75, height: 64),
    Row(isOwn: true, widthRatio: 0.4, height: 40),
    Row(isOwn: false, widthRatio: 0.6, height: 40),
    Row(isOwn: true, widthRatio: 0.55, height: 52),
  ]

  private static let avatarSize = RoomMetrics.avatarSize

  var body: some View {
    VStack(spacing: 12) {
      ForEach(Self.rows.indices, id: \.self) { index in
        row(Self.rows[index])
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
      $0.opacity(isDimmed ? 0.45 : 1)
    }
    .animation(.easeIn(duration: 0.2)) { $0.opacity(isShown ? 1 : 0) }
    .task {
      try? await Task.sleep(for: RoomMetrics.skeletonDelay)
      guard !Task.isCancelled else { return }
      isShown = true
      if !reduceMotion { isDimmed = true }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Loading messages")
  }

  private func row(_ row: Row) -> some View {
    HStack(alignment: .bottom, spacing: RoomMetrics.avatarSpacing) {
      if row.isOwn {
        Spacer(minLength: 0)
      } else {
        Circle()
          .fill(SysColors.surfaceVariant)
          .frame(width: Self.avatarSize, height: Self.avatarSize)
      }
      TwakeBubbleShape(isOwn: row.isOwn)
        .fill(SysColors.surfaceVariant)
        .frame(width: bubbleWidth * row.widthRatio, height: row.height)
      if !row.isOwn { Spacer(minLength: 0) }
    }
  }
}
