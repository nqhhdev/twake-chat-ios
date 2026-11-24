import DesignSystem
import Domain
import SwiftUI
import UIKit

extension PageStyle {
  /// The accent colour, or `nil` when the style has none.
  var accent: Color? {
    accentRGB.map { Color(red: $0.red, green: $0.green, blue: $0.blue) }
  }
}

/// The cover of a page (web `page_style`): its picture, filling the band, over its accent colour, which shows alone
/// when there is no picture or until it loads.
struct PageCover: View {
  let style: PageStyle
  let picture: @Sendable (MediaReference) async -> Data?
  @State private var image: UIImage?

  var body: some View {
    Rectangle()
      .fill(style.accent.map(AnyShapeStyle.init) ?? AnyShapeStyle(SysColors.primary))
      .frame(height: 120)
      .overlay {
        if let image {
          Image(uiImage: image).resizable().scaledToFill()
        }
      }
      .clipShape(RoundedRectangle(cornerRadius: 16))
      .accessibilityHidden(true)
      .task(id: style.cover?.source) {
        image = nil
        guard let cover = style.cover, let data = await picture(cover) else { return }
        image = UIImage(data: data)
      }
  }
}

extension View {
  /// A ring in the page's accent colour around an avatar of `size`, as the web draws the borders of a page in it.
  @ViewBuilder
  func pageAccentRing(_ style: PageStyle?, size: CGFloat) -> some View {
    if let accent = style?.accent {
      overlay(Circle().strokeBorder(accent, lineWidth: max(2, size / 24)))
    } else {
      self
    }
  }
}
