import SwiftUI

/// A list row shaped after twake-on-matrix `chat_list_item_style.dart`: 72 pt tall, 8 pt outer padding, 8 pt
/// between the leading view and the body, body padded 8 × 4, corner radius 4. Title in titleMedium (`onSurface`),
/// subtitle in bodyMedium (`textSecondary`).
public struct TwakeListRow<Leading: View, Trailing: View>: View {
  private let title: String
  private let subtitle: String?
  private let leading: Leading
  private let trailing: Trailing

  public init(
    _ title: String,
    subtitle: String? = nil,
    @ViewBuilder leading: () -> Leading,
    @ViewBuilder trailing: () -> Trailing
  ) {
    self.title = title
    self.subtitle = subtitle
    self.leading = leading()
    self.trailing = trailing()
  }

  public var body: some View {
    HStack(spacing: 0) {
      leading.padding(.trailing, 8)
      VStack(alignment: .leading, spacing: 0) {
        Text(title)
          .textStyle(TextStyles.titleMedium)
          .foregroundStyle(SysColors.onSurface)
        if let subtitle {
          Text(subtitle)
            .textStyle(TextStyles.bodyMedium)
            .foregroundStyle(SysColors.textSecondary)
        }
      }
      .lineLimit(1)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 8)
      .padding(.vertical, 4)
      trailing
    }
    .padding(8)
    .frame(minHeight: 72)
    .contentShape(RoundedRectangle(cornerRadius: 4))
  }
}

extension TwakeListRow where Leading == EmptyView, Trailing == EmptyView {
  public init(_ title: String, subtitle: String? = nil) {
    self.init(title, subtitle: subtitle, leading: { EmptyView() }, trailing: { EmptyView() })
  }
}

extension TwakeListRow where Trailing == EmptyView {
  public init(_ title: String, subtitle: String? = nil, @ViewBuilder leading: () -> Leading) {
    self.init(title, subtitle: subtitle, leading: leading, trailing: { EmptyView() })
  }
}

#Preview("List row, light") {
  ListRowPreview().preferredColorScheme(.light)
}

#Preview("List row, dark") {
  ListRowPreview().preferredColorScheme(.dark)
}

private struct ListRowPreview: View {
  var body: some View {
    VStack(spacing: 0) {
      TwakeListRow("Alice", subtitle: "See you tomorrow") {
        Circle().fill(SysColors.primaryContainer).frame(width: 56, height: 56)
      } trailing: {
        Text("10:42").textStyle(TextStyles.labelSmall).foregroundStyle(SysColors.textSecondary)
      }
      TwakeListRow("Settings")
    }
    .background(SysColors.background)
  }
}
