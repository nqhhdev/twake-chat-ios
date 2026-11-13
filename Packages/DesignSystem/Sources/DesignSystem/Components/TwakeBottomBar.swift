import SwiftUI

/// One destination of the Twake navigation (twake-on-matrix `AdaptiveDestinationEnum`): its value, label and icon. The
/// icons mix symbols and the user's avatar, so each is type-erased.
public struct TwakeNavigationItem<Selection: Hashable> {
  public let value: Selection
  public let title: String
  public let icon: (_ isSelected: Bool) -> AnyView

  public init<Icon: View>(
    value: Selection, title: String, @ViewBuilder icon: @escaping (_ isSelected: Bool) -> Icon
  ) {
    self.value = value
    self.title = title
    self.icon = { AnyView(icon($0)) }
  }
}

/// The bottom navigation bar of twake-on-matrix `AppAdaptiveScaffoldBodyView` and `themes.dart`
/// `bottomNavigationBarTheme`, used on a phone held upright and on a folded Duo: `surface` background with a 1 pt top
/// border, the selected item and its 11 pt label in `primary`, the others in `tertiary`. The items take 56 pt and the
/// background runs on under the home indicator, so nothing empty sits below the labels.
public struct TwakeBottomBar<Selection: Hashable>: View {
  public static var itemsHeight: CGFloat { 56 }

  @Binding private var selection: Selection
  private let items: [TwakeNavigationItem<Selection>]

  public init(selection: Binding<Selection>, items: [TwakeNavigationItem<Selection>]) {
    self._selection = selection
    self.items = items
  }

  public var body: some View {
    HStack(spacing: 0) {
      ForEach(items.indices, id: \.self) { index in
        let item = items[index]
        let isSelected = item.value == selection
        Button {
          selection = item.value
        } label: {
          VStack(spacing: 2) {
            item.icon(isSelected).frame(height: 28)
            Text(item.title).textStyle(TextStyles.labelSmall.with(size: 11))
          }
          .foregroundStyle(isSelected ? SysColors.primary : SysColors.tertiary)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
      }
    }
    .frame(height: Self.itemsHeight)
    .frame(maxWidth: .infinity)
    .background(SysColors.surface, ignoresSafeAreaEdges: .bottom)
    .overlay(alignment: .top) {
      // `navBarBorder`: surfaceTint at the opacityLayer3 state layer (0.16).
      Rectangle().fill(SysColors.surfaceTint.opacity(0.16)).frame(height: 1)
    }
  }
}

/// The navigation rail of twake-on-matrix `AdaptiveScaffoldPrimaryNavigation`, used beside the chat list on a wide or
/// landscape screen (an unfolded Duo, an iPad, a phone on its side): 80 pt wide on `surface`, 32 pt from the top, each
/// destination's icon over its labelMedium label, the selected one in `primary` on a `secondaryContainer` pill, and
/// the user's avatar under a divider at the bottom.
public struct TwakeNavigationRail<Selection: Hashable, Footer: View>: View {
  /// `AdaptiveScaffoldPrimaryNavigationStyle.primaryNavigationWidth`.
  public static var width: CGFloat { 80 }

  @Binding private var selection: Selection
  private let items: [TwakeNavigationItem<Selection>]
  private let footer: Footer

  public init(
    selection: Binding<Selection>, items: [TwakeNavigationItem<Selection>],
    @ViewBuilder footer: () -> Footer
  ) {
    self._selection = selection
    self.items = items
    self.footer = footer()
  }

  public var body: some View {
    VStack(spacing: 12) {
      ForEach(items.indices, id: \.self) { index in
        let item = items[index]
        let isSelected = item.value == selection
        Button {
          selection = item.value
        } label: {
          VStack(spacing: 4) {
            item.icon(isSelected)
              .frame(width: 56, height: 32)
              .background(isSelected ? SysColors.secondaryContainer : ColorToken(0), in: Capsule())
            Text(item.title)
              .textStyle(TextStyles.labelMedium)
              .lineLimit(1)
          }
          .foregroundStyle(isSelected ? SysColors.primary : SysColors.onSurface)
          .frame(width: Self.width)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
      }
      Spacer(minLength: 0)
      Rectangle().fill(ColorToken(0xFFD7_D8D9)).frame(width: 48, height: 2).padding(.bottom, 16)
      footer.padding(.bottom, 8)
    }
    .padding(.vertical, 32)
    .frame(width: Self.width)
    .frame(maxHeight: .infinity)
    .background(SysColors.surface, ignoresSafeAreaEdges: .all)
  }
}
