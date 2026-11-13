import Foundation

/// A message's formatted body (Matrix `org.matrix.custom.html`) as styled text, as the web client draws it (sanitised
/// HTML): bold, italic, struck, inline code, code blocks, links (mentions included), quotes, lists, headings and line
/// breaks. Any other tag keeps its text only. The reply fallback (`mx-reply`), scripts and styles are dropped, and a link
/// is kept only for `http`, `https`, `mailto` and `matrix`, so nothing in a message can run or load anything. Bare web
/// addresses in the text become links too. The result uses Foundation attributes only (`inlinePresentationIntent`,
/// `link`), which SwiftUI `Text` draws.
public enum MatrixHTML {
  public static func attributedString(from html: String) -> AttributedString {
    var builder = Builder()
    var text = ""
    var index = html.startIndex
    while index < html.endIndex {
      if html[index] == "<", let close = html[index...].firstIndex(of: ">") {
        builder.write(text: text)
        text = ""
        builder.tag(String(html[html.index(after: index)..<close]))
        index = html.index(after: close)
      } else {
        text.append(html[index])
        index = html.index(after: index)
      }
    }
    builder.write(text: text)
    return builder.finish()
  }

  /// The text with every web address that is not already a link turned into one, for a message without HTML.
  public static func linkingBareAddresses(_ text: AttributedString) -> AttributedString {
    let plain = String(text.characters)
    guard let detector = linkDetector, plain.contains(".") else { return text }
    var result = text
    for match in detector.matches(in: plain, range: NSRange(plain.startIndex..., in: plain)) {
      guard let url = match.url, ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
        let range = Range(match.range, in: plain),
        let start = AttributedString.Index(range.lowerBound, within: result),
        let end = AttributedString.Index(range.upperBound, within: result),
        result[start..<end].runs.allSatisfy({ $0.link == nil })
      else { continue }
      result[start..<end].link = url
    }
    return result
  }

  /// The text with its HTML entities (`&amp;`, `&#39;`, `&#x1F600;` …) replaced by their characters.
  static func decodeEntities(_ text: String) -> String {
    guard text.contains("&") else { return text }
    var result = ""
    var index = text.startIndex
    while index < text.endIndex {
      if text[index] == "&", let end = text[index...].prefix(12).firstIndex(of: ";") {
        let name = String(text[text.index(after: index)..<end])
        if let character = character(named: name) {
          result.append(character)
          index = text.index(after: end)
          continue
        }
      }
      result.append(text[index])
      index = text.index(after: index)
    }
    return result
  }

  private static func character(named name: String) -> Character? {
    switch name {
    case "amp": return "&"
    case "lt": return "<"
    case "gt": return ">"
    case "quot": return "\""
    case "apos": return "'"
    case "nbsp": return " "
    default:
      let number: UInt32? =
        if name.hasPrefix("#x") || name.hasPrefix("#X") {
          UInt32(name.dropFirst(2), radix: 16)
        } else if name.hasPrefix("#") {
          UInt32(name.dropFirst())
        } else {
          nil
        }
      return number.flatMap(Unicode.Scalar.init).map(Character.init)
    }
  }

  /// Finds web addresses in text written outside a link.
  static let linkDetector = try? NSDataDetector(
    types: NSTextCheckingResult.CheckingType.link.rawValue)
}

/// Writes the text with the styles of the tags open around it.
private struct Builder {
  private var output = AttributedString()
  private var bold = 0
  private var italic = 0
  private var strike = 0
  private var code = 0
  private var pre = 0
  /// Inside `mx-reply`, `script` or `style`: nothing is written.
  private var skipped = 0
  private var links: [URL?] = []
  private var lists: [(ordered: Bool, next: Int)] = []
  private var quoteDepth = 0
  /// Nothing has been written on the current line yet.
  private var atLineStart = true

  mutating func tag(_ raw: String) {
    if raw.hasPrefix("!") || raw.hasPrefix("?") { return }
    let isClosing = raw.hasPrefix("/")
    let body = isClosing ? raw.dropFirst() : Substring(raw)
    let name = body.prefix { $0.isLetter || $0.isNumber || $0 == "-" }.lowercased()
    switch name {
    case "mx-reply", "script", "style":
      skipped += isClosing ? (skipped > 0 ? -1 : 0) : 1
    case "b", "strong": bold += isClosing ? -1 : 1
    case "i", "em", "cite": italic += isClosing ? -1 : 1
    case "del", "s", "strike": strike += isClosing ? -1 : 1
    case "code": code += isClosing ? -1 : 1
    case "pre":
      breakLine()
      pre += isClosing ? -1 : 1
    case "a":
      if isClosing {
        _ = links.popLast()
      } else {
        links.append(Self.safeLink(Self.attribute("href", in: body)))
      }
    case "br": newLine()
    case "p", "div", "table", "tr", "hr": breakLine()
    case "h1", "h2", "h3", "h4", "h5", "h6":
      breakLine()
      bold += isClosing ? -1 : 1
    case "blockquote":
      breakLine()
      quoteDepth += isClosing ? -1 : 1
    case "ul", "ol":
      breakLine()
      if isClosing {
        _ = lists.popLast()
      } else {
        let start = Self.attribute("start", in: body).flatMap { Int($0) } ?? 1
        lists.append((ordered: name == "ol", next: start))
      }
    case "li":
      guard !isClosing else { return }
      breakLine()
      let depth = max(lists.count - 1, 0)
      var marker = String(repeating: "    ", count: depth)
      if let last = lists.indices.last, lists[last].ordered {
        marker += "\(lists[last].next). "
        lists[last].next += 1
      } else {
        marker += "• "
      }
      append(marker, styled: false)
    case "img":
      if let alt = Self.attribute("alt", in: body) { write(text: alt) }
    case "td", "th":
      if !isClosing, !atLineStart { append(" ", styled: false) }
    default: break
    }
    bold = max(bold, 0)
    italic = max(italic, 0)
    strike = max(strike, 0)
    code = max(code, 0)
    pre = max(pre, 0)
    quoteDepth = max(quoteDepth, 0)
  }

  mutating func write(text raw: String) {
    guard skipped == 0, !raw.isEmpty else { return }
    let text = MatrixHTML.decodeEntities(raw)
    if pre > 0 {
      let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
      for (offset, line) in lines.enumerated() {
        if offset > 0 { newLine() }
        if !line.isEmpty { append(String(line), styled: true) }
      }
      return
    }
    var collapsed = text.replacing(#/\s+/#, with: " ")
    if atLineStart || output.characters.last == " " {
      collapsed = String(collapsed.drop { $0 == " " })
    }
    guard !collapsed.isEmpty else { return }
    append(collapsed, styled: true)
  }

  /// Ends the current line, unless nothing is on it.
  private mutating func breakLine() {
    if !atLineStart { newLine() }
  }

  private mutating func newLine() {
    guard !output.characters.isEmpty else { return }
    // A space before the line end is left out.
    if output.characters.last == " " {
      output.removeSubrange(output.characters.index(before: output.endIndex)..<output.endIndex)
    }
    output += AttributedString("\n")
    atLineStart = true
  }

  private mutating func append(_ text: String, styled: Bool) {
    if atLineStart, quoteDepth > 0 {
      output += AttributedString(String(repeating: "│ ", count: quoteDepth))
    }
    atLineStart = false
    var piece = AttributedString(text)
    guard styled else {
      output += piece
      return
    }
    var intent: InlinePresentationIntent = []
    if bold > 0 { intent.insert(.stronglyEmphasized) }
    if italic > 0 || quoteDepth > 0 { intent.insert(.emphasized) }
    if strike > 0 { intent.insert(.strikethrough) }
    if code > 0 || pre > 0 { intent.insert(.code) }
    if !intent.isEmpty { piece.inlinePresentationIntent = intent }
    if let link = links.last {
      if let link { piece.link = link }
    } else if code == 0, pre == 0 {
      Self.linkBareAddresses(in: &piece, text: text)
    }
    output += piece
  }

  func finish() -> AttributedString {
    var result = output
    while let last = result.characters.last, last.isWhitespace {
      result.removeSubrange(result.characters.index(before: result.endIndex)..<result.endIndex)
    }
    return result
  }

  private static func linkBareAddresses(in piece: inout AttributedString, text: String) {
    guard let detector = MatrixHTML.linkDetector, text.contains(".") else { return }
    let range = NSRange(text.startIndex..., in: text)
    for match in detector.matches(in: text, range: range) {
      guard let url = safeLink(match.url?.absoluteString),
        let textRange = Range(match.range, in: text),
        let start = AttributedString.Index(textRange.lowerBound, within: piece),
        let end = AttributedString.Index(textRange.upperBound, within: piece)
      else { continue }
      piece[start..<end].link = url
    }
  }

  /// The link if its scheme is one a message may carry; `nil` for `javascript:` and the like.
  private static func safeLink(_ href: String?) -> URL? {
    guard let href, let url = URL(string: href.trimmingCharacters(in: .whitespaces)),
      let scheme = url.scheme?.lowercased(), ["http", "https", "mailto", "matrix"].contains(scheme)
    else { return nil }
    return url
  }

  /// The value of an attribute in a tag, quoted with `"` or `'`, or bare.
  private static func attribute(_ name: String, in tag: Substring) -> String? {
    guard
      let match = tag.range(
        of: #"(^|\s)"# + name + #"\s*=\s*"#, options: [.regularExpression, .caseInsensitive])
    else { return nil }
    let rest = tag[match.upperBound...]
    guard let quote = rest.first, quote == "\"" || quote == "'" else {
      return String(rest.prefix { !$0.isWhitespace && $0 != "/" })
    }
    let value = rest.dropFirst().prefix { $0 != quote }
    return MatrixHTML.decodeEntities(String(value))
  }
}
