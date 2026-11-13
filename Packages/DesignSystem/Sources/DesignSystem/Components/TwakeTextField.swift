import SwiftUI

/// The text field of `themes.dart` `inputDecorationTheme`: no border, corner radius 10, text in bodyLarge, hint in
/// bodyLarge at 17 pt in `neutralVariant[60]`, cursor in `primary`.
public struct TwakeTextField: View {
  private let hint: String
  @Binding private var text: String

  public init(_ hint: String, text: Binding<String>) {
    self.hint = hint
    self._text = text
  }

  public var body: some View {
    TextField(text: $text) {
      Text(hint)
        .textStyle(TextStyles.bodyLarge.with(size: 17))
        .foregroundStyle(TwakeTextField.hintColor)
    }
    .textStyle(TextStyles.bodyLarge)
    .foregroundStyle(SysColors.onSurface)
    .tint(SysColors.primary)
    .textFieldStyle(.plain)
    .padding(.vertical, 12)
    .contentShape(RoundedRectangle(cornerRadius: TwakeRadius.small))
  }

  /// `LinagoraRefColors.material().neutralVariant[60]`.
  public static let hintColor = RefColors.neutralVariant[tone: 60]!
}

#Preview("Text field, light") {
  TextFieldPreview().preferredColorScheme(.light)
}

#Preview("Text field, dark") {
  TextFieldPreview().preferredColorScheme(.dark)
}

private struct TextFieldPreview: View {
  @State private var empty = ""
  @State private var filled = "@alice:example.org"

  var body: some View {
    VStack {
      TwakeTextField("Username", text: $empty)
      TwakeTextField("Username", text: $filled)
    }
    .padding()
    .background(SysColors.background)
  }
}
