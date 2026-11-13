import SwiftUI

/// The breakpoints of twake-on-matrix `ResponsiveUtils` and `AppAdaptiveScaffold`: under 905 pt wide the app shows one
/// column (a phone, a folded Duo, a phone in landscape); from 905 pt it shows the chat list beside the chat (an
/// unfolded Duo, an iPad). The list column is `bodyRadioWidth` wide.
public enum TwakeLayout {
  /// `ResponsiveUtils.minTabletWidth`.
  public static let minTwoColumnWidth: CGFloat = 905
  /// `ResponsiveUtils.bodyRadioWidth`: the chat list column in the two-column layout.
  public static let listColumnWidth: CGFloat = 472
  /// `MessageStyle.messageBubbleDesktopMaxWidth`.
  public static let bubbleMaxWidth: CGFloat = 520
  /// `MessageStyle.messageBubbleMobileRatioMaxWidth`: a bubble's share of a narrow screen.
  public static let bubbleMobileRatio: CGFloat = 0.88
  /// The width the sign-in screens keep on a wide screen, so their buttons do not stretch across it.
  public static let formMaxWidth: CGFloat = 472

  public static func isTwoColumn(width: CGFloat) -> Bool {
    width >= minTwoColumnWidth
  }

  /// The widest a message bubble may be in a chat column of `width`.
  public static func bubbleWidth(in width: CGFloat) -> CGFloat {
    min(bubbleMaxWidth, width * bubbleMobileRatio)
  }
}
