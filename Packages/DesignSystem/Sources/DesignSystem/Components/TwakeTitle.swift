import SwiftUI

extension View {
  /// The title of twake-on-matrix `TwakeAppBar` on mobile: centred, in bodyLarge1 `onSurface`, on `background`.
  public func twakeTitle(_ title: String) -> some View {
    navigationTitle(title)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .principal) {
          Text(title).textStyle(TextStyles.bodyLarge1).foregroundStyle(SysColors.onSurface)
        }
      }
      .toolbarBackground(SysColors.background, for: .navigationBar)
  }
}
