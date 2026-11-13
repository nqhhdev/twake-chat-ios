import SwiftUI

/// The app bar of `themes.dart` `appBarTheme`: 48 pt tall (`AppConfig.toolbarHeight` on mobile), title spacing 0
/// (the title follows the leading view directly), title in titleLarge, no elevation when scrolled under.
///
/// The background is `LinagoraSysColors.onPrimary` in both modes and the foreground `onBackground` /
/// `onBackgroundDark`, exactly as `themes.dart` sets them.
public struct TwakeAppBar<Leading: View, Trailing: View>: View {
  /// `AppConfig.toolbarHeight` on mobile.
  public static var height: CGFloat { 48 }

  private let title: String
  private let leading: Leading
  private let trailing: Trailing

  public init(
    _ title: String,
    @ViewBuilder leading: () -> Leading,
    @ViewBuilder trailing: () -> Trailing
  ) {
    self.title = title
    self.leading = leading()
    self.trailing = trailing()
  }

  public var body: some View {
    HStack(spacing: 0) {
      leading
      Text(title)
        .textStyle(TextStyles.titleLarge)
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
      trailing
    }
    .padding(.horizontal, 4)
    .frame(height: Self.height)
    .foregroundStyle(SysColors.onBackground)
    .background(Color(argb: SysColors.onPrimary.light))
  }
}

extension TwakeAppBar where Leading == EmptyView, Trailing == EmptyView {
  public init(_ title: String) {
    self.init(title, leading: { EmptyView() }, trailing: { EmptyView() })
  }
}

#Preview("App bar, light") {
  AppBarPreview().preferredColorScheme(.light)
}

#Preview("App bar, dark") {
  AppBarPreview().preferredColorScheme(.dark)
}

private struct AppBarPreview: View {
  var body: some View {
    VStack(spacing: 0) {
      TwakeAppBar("Chats") {
        Image(systemName: "chevron.left").frame(width: 48, height: 48)
      } trailing: {
        Image(systemName: "magnifyingglass").frame(width: 48, height: 48)
      }
      TwakeAppBar("Settings")
      Spacer()
    }
  }
}
