import SwiftUI

/// Formatted text the reader can select any part of and copy, with its links still working, as WhatsApp's and
/// Telegram's "Select Text" show a message.
///
/// UIKit, as ADR 0004 allows inside DesignSystem: SwiftUI's `textSelection(.enabled)` on iOS only copies the whole
/// text, so this wraps a read-only `UITextView`, which has the system's partial selection.
public struct SelectableText: UIViewRepresentable {
  private let text: NSAttributedString

  /// `text` keeps its links, bold, italic, code and strikethrough; other attributes are dropped.
  public init(_ text: AttributedString) {
    self.text = Self.attributed(text)
  }

  public func makeUIView(context: Context) -> UITextView {
    let view = UITextView()
    view.isEditable = false
    view.isSelectable = true
    view.backgroundColor = .clear
    view.adjustsFontForContentSizeCategory = true
    view.dataDetectorTypes = []
    view.tintColor = Self.uiColor(SysColors.primary)
    view.linkTextAttributes = [.foregroundColor: Self.uiColor(SysColors.primary)]
    view.textContainerInset = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
    view.delegate = context.coordinator
    return view
  }

  public func updateUIView(_ view: UITextView, context: Context) {
    context.coordinator.openURL = context.environment.openURL
    if view.attributedText != text { view.attributedText = text }
  }

  public func makeCoordinator() -> Coordinator { Coordinator() }

  /// Opens a tapped link the way the rest of the app does, through SwiftUI's `openURL`, not straight in Safari.
  public final class Coordinator: NSObject, UITextViewDelegate {
    var openURL: OpenURLAction?

    public func textView(
      _ textView: UITextView, primaryActionFor textItem: UITextItem, defaultAction: UIAction
    ) -> UIAction? {
      guard case .link(let url) = textItem.content, let openURL else { return defaultAction }
      return UIAction { _ in openURL(url) }
    }
  }

  /// `text` in UIKit attributes, at the body size of Dynamic Type, in the label colour.
  public static func attributed(_ text: AttributedString) -> NSAttributedString {
    let body = UIFont.preferredFont(forTextStyle: .body)
    let result = NSMutableAttributedString()
    for run in text.runs {
      let intent = run.inlinePresentationIntent ?? []
      var attributes: [NSAttributedString.Key: Any] = [
        .font: font(for: intent, base: body), .foregroundColor: UIColor.label,
      ]
      if intent.contains(.strikethrough) {
        attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
      }
      if let link = run.link { attributes[.link] = link }
      result.append(
        NSAttributedString(string: String(text[run.range].characters), attributes: attributes))
    }
    return result
  }

  /// The token as a UIKit colour that follows light and dark mode.
  private static func uiColor(_ token: ColorToken) -> UIColor {
    UIColor { traits in
      UIColor(token.color(for: traits.userInterfaceStyle == .dark ? .dark : .light))
    }
  }

  private static func font(for intent: InlinePresentationIntent, base: UIFont) -> UIFont {
    if intent.contains(.code) {
      return .monospacedSystemFont(ofSize: base.pointSize, weight: .regular)
    }
    var traits: UIFontDescriptor.SymbolicTraits = []
    if intent.contains(.stronglyEmphasized) { traits.insert(.traitBold) }
    if intent.contains(.emphasized) { traits.insert(.traitItalic) }
    guard !traits.isEmpty, let descriptor = base.fontDescriptor.withSymbolicTraits(traits) else {
      return base
    }
    return UIFont(descriptor: descriptor, size: 0)
  }
}
