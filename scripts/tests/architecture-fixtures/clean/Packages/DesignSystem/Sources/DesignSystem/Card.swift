import SwiftUI

@available(iOS 26, *)
struct GlassCard: View {
  var body: some View { Color.clear }
}

public struct Card: View {
  public var body: some View {
    if #available(iOS 26, *) {
      GlassCard()
    } else {
      Color.gray
    }
  }
}
