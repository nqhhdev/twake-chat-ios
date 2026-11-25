import Foundation

/// A format of the composer's bar. The Markdown stays in the text, as on the web: a format writes its syntax around
/// the selection and takes it off when it is already there; sending turns it into `formatted_body`.
enum TextFormat: CaseIterable, Sendable {
  case bold, italic, strike, code, codeBlock, link

  /// What VoiceOver reads for the button.
  var label: String {
    switch self {
    case .bold: "Bold"
    case .italic: "Italic"
    case .strike: "Strikethrough"
    case .code: "Code"
    case .codeBlock: "Code block"
    case .link: "Link"
    }
  }

  var systemImage: String {
    switch self {
    case .bold: "bold"
    case .italic: "italic"
    case .strike: "strikethrough"
    case .code: "chevron.left.forwardslash.chevron.right"
    case .codeBlock: "curlybraces.square"
    case .link: "link"
    }
  }
}

/// The text after a format and the part of it to select. Offsets count characters (`Character`), not bytes.
struct FormattedText: Equatable {
  var text: String
  var selection: Range<Int>
}

/// The Markdown link a selection touches, or the selected text, which the « Add a link » dialog edits.
struct LinkTarget: Equatable {
  var range: Range<Int>
  var text: String
  var url: String
}

/// The Markdown each format writes, the same marks the web composer writes.
enum TextFormatting {
  /// What `format` does to `text` selected over `selection`. A link goes through `linkTarget` and `link` instead.
  static func apply(_ format: TextFormat, to text: String, selection: Range<Int>) -> FormattedText {
    let characters = Array(text)
    let selection = selection.clamped(to: 0..<characters.count)
    switch format {
    case .bold: return wrap(characters, selection, "**", "**")
    case .italic: return wrap(characters, selection, "_", "_")
    case .strike: return wrap(characters, selection, "~~", "~~")
    case .code: return wrap(characters, selection, "`", "`")
    case .codeBlock: return codeBlock(characters, selection)
    case .link: return FormattedText(text: text, selection: selection)
    }
  }

  /// Writes `open` and `close` around the selection, or takes them off when they are already around or inside it.
  /// Spaces at either end stay outside: « **bold **» would not be bold.
  private static func wrap(
    _ text: [Character], _ selection: Range<Int>, _ open: String, _ close: String
  ) -> FormattedText {
    let open = Array(open)
    let close = Array(close)
    let selected = text[selection]
    let leading = selected.prefix(while: \.isWhitespace).count
    let isBlank = leading == selected.count
    let trailing = isBlank ? 0 : selected.reversed().prefix(while: \.isWhitespace).count
    let from = selection.lowerBound + leading
    let to = isBlank ? from : selection.upperBound - trailing
    let inner = Array(text[from..<to])
    if from >= open.count, to + close.count <= text.count,
      Array(text[(from - open.count)..<from]) == open, Array(text[to..<(to + close.count)]) == close
    {
      let start = from - open.count
      return replacing(
        text, start..<(to + close.count), with: inner, select: start..<(start + inner.count))
    }
    if inner.count >= open.count + close.count, inner.starts(with: open),
      inner.reversed().starts(with: close.reversed())
    {
      let bare = Array(inner[open.count..<(inner.count - close.count)])
      return replacing(text, from..<to, with: bare, select: from..<(from + bare.count))
    }
    return replacing(
      text, from..<to, with: open + inner + close, select: (from + open.count)..<(to + open.count))
  }

  /// Puts the selection between fences on lines of their own, or takes the fences off.
  private static func codeBlock(_ text: [Character], _ selection: Range<Int>) -> FormattedText {
    let open = Array("```\n")
    let close = Array("\n```")
    let selected = Array(text[selection])
    let start = selection.lowerBound
    let end = selection.upperBound
    let at = start - open.count
    if at >= 0, at == 0 || text[at - 1] == "\n", Array(text[at..<start]) == open,
      end + close.count <= text.count, Array(text[end..<(end + close.count)]) == close
    {
      return replacing(
        text, at..<(end + close.count), with: selected, select: at..<(at + selected.count))
    }
    let before: [Character] = start > 0 && text[start - 1] != "\n" ? ["\n"] : []
    let after: [Character] = end < text.count && text[end] != "\n" ? ["\n"] : []
    let codeStart = start + before.count + open.count
    return replacing(
      text, selection, with: before + open + selected + close + after,
      select: codeStart..<(codeStart + selected.count))
  }

  /// The Markdown link `[text](url)` the selection is inside, else the selection itself as the link's text.
  static func linkTarget(in text: String, selection: Range<Int>) -> LinkTarget {
    let characters = Array(text)
    let selection = selection.clamped(to: 0..<characters.count)
    for match in text.matches(of: #/\[([^\]\n]*)\]\(([^)\s]*)\)/#) {
      let from = text.distance(from: text.startIndex, to: match.range.lowerBound)
      let to = text.distance(from: text.startIndex, to: match.range.upperBound)
      if selection.lowerBound >= from, selection.upperBound <= to {
        return LinkTarget(
          range: from..<to, text: String(match.output.1), url: String(match.output.2))
      }
    }
    return LinkTarget(range: selection, text: String(characters[selection]), url: "")
  }

  /// Writes the link over the target, the caret after it; the address is the text when the text is empty.
  static func link(_ target: LinkTarget, in text: String, label: String, url: String)
    -> FormattedText
  {
    let characters = Array(text)
    let range = target.range.clamped(to: 0..<characters.count)
    let link = Array(
      "[\(label.trimmingCharacters(in: .whitespaces).isEmpty ? url : label)](\(url))")
    let end = range.lowerBound + link.count
    return replacing(characters, range, with: link, select: end..<end)
  }

  /// The address to link to (`www.` gets `https://`), `nil` when it is not a web address.
  static func webAddress(_ input: String) -> String? {
    let typed = input.trimmingCharacters(in: .whitespacesAndNewlines)
    let address = typed.lowercased().hasPrefix("www.") ? "https://" + typed : typed
    guard !address.contains(where: { $0.isWhitespace || $0 == "(" || $0 == ")" }),
      let url = URL(string: address), let scheme = url.scheme?.lowercased(),
      scheme == "http" || scheme == "https", let host = url.host(), !host.isEmpty
    else { return nil }
    return address
  }

  private static func replacing(
    _ text: [Character], _ range: Range<Int>, with insert: [Character], select: Range<Int>
  ) -> FormattedText {
    var text = text
    text.replaceSubrange(range, with: insert)
    return FormattedText(text: String(text), selection: select)
  }
}
