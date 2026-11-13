import SwiftUI

/// The round action button that floats at the bottom corner of a list, such as "New chat": Liquid Glass tinted with
/// `primary` on iOS 26 and later, a filled `primary` circle with a soft shadow before. The version check lives here
/// (ADR 0002).
public struct TwakeFloatingButton: View {
  private let title: String
  private let systemImage: String
  private let action: () -> Void

  public init(_ title: String, systemImage: String, action: @escaping () -> Void) {
    self.title = title
    self.systemImage = systemImage
    self.action = action
  }

  public var body: some View {
    let label = Image(systemName: systemImage)
      .font(.system(size: 22, weight: .semibold))
      .frame(width: 56, height: 56)
    Group {
      if #available(iOS 26, *) {
        Button(action: action) { label }
          .buttonStyle(.glassProminent)
          .buttonBorderShape(.circle)
          .tint(SysColors.primary)
      } else {
        Button(action: action) {
          label
            .foregroundStyle(SysColors.onPrimary)
            .background(SysColors.primary, in: Circle())
            .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
      }
    }
    .accessibilityLabel(title)
    .padding(16)
  }
}
