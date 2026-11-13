import SwiftUI

extension View {
  /// The system tab bar shrinks while the content scrolls down and comes back when it scrolls up, as in Apple's apps on
  /// iOS 26 and later; on earlier versions it stays as it is. The version check lives here (ADR 0002).
  public func twakeTabBarMinimizesOnScroll() -> some View {
    modifier(TabBarMinimizesOnScroll())
  }
}

private struct TabBarMinimizesOnScroll: ViewModifier {
  func body(content: Content) -> some View {
    if #available(iOS 26, *) {
      content.tabBarMinimizeBehavior(.onScrollDown)
    } else {
      content
    }
  }
}
