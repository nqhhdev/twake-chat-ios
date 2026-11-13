import SwiftUI

/// A chat bubble as Telegram and iMessage draw one inside a group: 18 pt corners, 6 pt on the sender's side where the
/// bubble touches its neighbour, and a small tail at the bottom on the sender's side for the last bubble of a group.
/// Own bubbles have their tail on the trailing side, others on the leading side.
public struct TwakeBubbleShape: Shape {
  public static let largeRadius: CGFloat = 18
  public static let smallRadius: CGFloat = 6

  public var isOwn: Bool
  public var isFirst: Bool
  public var isLast: Bool

  public init(isOwn: Bool, isFirst: Bool = true, isLast: Bool = true) {
    self.isOwn = isOwn
    self.isFirst = isFirst
    self.isLast = isLast
  }

  public func path(in rect: CGRect) -> Path {
    let large = Self.largeRadius
    let small = Self.smallRadius
    // The sender's side: rounded small where the group continues, and at the bottom of the last bubble (the tail).
    let senderTop = isFirst ? large : small
    let senderBottom = isLast ? small : small
    let radii =
      isOwn
      ? RectangleCornerRadii(
        topLeading: large, bottomLeading: large, bottomTrailing: senderBottom,
        topTrailing: senderTop)
      : RectangleCornerRadii(
        topLeading: senderTop, bottomLeading: senderBottom, bottomTrailing: large,
        topTrailing: large)
    let body = UnevenRoundedRectangle(cornerRadii: radii, style: .continuous).path(in: rect)
    guard isLast else { return body }
    return body.union(tail(in: rect))
  }

  /// A curl at the bottom corner on the sender's side, drawn for own bubbles and mirrored for others.
  private func tail(in rect: CGRect) -> Path {
    var tail = Path()
    let x = rect.maxX
    let y = rect.maxY
    tail.move(to: CGPoint(x: x - 10, y: y - 12))
    tail.addQuadCurve(to: CGPoint(x: x + 5, y: y), control: CGPoint(x: x - 8, y: y - 1))
    tail.addQuadCurve(to: CGPoint(x: x - 16, y: y - 1), control: CGPoint(x: x - 6, y: y + 1))
    tail.closeSubpath()
    guard !isOwn else { return tail }
    return tail.applying(
      CGAffineTransform(translationX: rect.minX + rect.maxX, y: 0).scaledBy(x: -1, y: 1))
  }
}

#Preview("Bubbles") {
  VStack(alignment: .trailing, spacing: 2) {
    Text("First").padding(10).background(
      .blue.opacity(0.2), in: TwakeBubbleShape(isOwn: true, isLast: false))
    Text("Middle").padding(10).background(
      .blue.opacity(0.2), in: TwakeBubbleShape(isOwn: true, isFirst: false, isLast: false))
    Text("Last of the group").padding(10).background(
      .blue.opacity(0.2), in: TwakeBubbleShape(isOwn: true, isFirst: false))
    Text("Theirs").padding(10).background(.gray.opacity(0.2), in: TwakeBubbleShape(isOwn: false))
      .frame(maxWidth: .infinity, alignment: .leading)
  }
  .padding()
}
