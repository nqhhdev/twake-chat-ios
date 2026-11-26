import Foundation

enum RichMarkdown {
  static let marker = "||"
  static let hiddenText = "[Spoiler]"

  struct Segment: Equatable {
    let text: String
    let isSpoiler: Bool
  }

  static func segments(_ text: String) -> [Segment] {
    var segments: [Segment] = []
    var rest = Substring(text)
    while let open = rest.range(of: marker),
      let close = rest[open.upperBound...].range(of: marker),
      open.upperBound < close.lowerBound
    {
      let before = rest[..<open.lowerBound]
      if !before.isEmpty { segments.append(Segment(text: String(before), isSpoiler: false)) }
      segments.append(
        Segment(text: String(rest[open.upperBound..<close.lowerBound]), isSpoiler: true))
      rest = rest[close.upperBound...]
    }
    if !rest.isEmpty { segments.append(Segment(text: String(rest), isSpoiler: false)) }
    return segments
  }

  static func content(_ text: String, emotes: [String: String] = [:]) -> (
    body: String, html: String
  )? {
    let segments = segments(text)
    let hasSpoiler = segments.contains(where: \.isSpoiler)
    guard hasSpoiler || !usedEmotes(in: text, emotes: emotes).isEmpty else { return nil }
    let body = segments.map { $0.isSpoiler ? hiddenText : $0.text }.joined()
    let html = segments.map { segment in
      let inner = inlineHTML(segment.text, emotes: emotes)
      return segment.isSpoiler ? "<span data-mx-spoiler>\(inner)</span>" : inner
    }.joined()
    return (body, html)
  }

  static func usedEmotes(in text: String, emotes: [String: String]) -> [String] {
    guard !emotes.isEmpty else { return [] }
    return text.matches(of: shortcodePattern).compactMap { match in
      let shortcode = String(match.output.1)
      return emotes[shortcode] == nil ? nil : shortcode
    }
  }

  nonisolated(unsafe) static let shortcodePattern = /:([A-Za-z0-9_+\-.]+):/

  static func replacingEmotes(in html: String, emotes: [String: String]) -> String {
    guard !emotes.isEmpty else { return html }
    return html.replacing(shortcodePattern) { match in
      let shortcode = String(match.output.1)
      guard let url = emotes[shortcode] else { return String(match.output.0) }
      let alt = escape(":\(shortcode):")
      return
        "<img data-mx-emoticon src=\"\(escape(url))\" alt=\"\(alt)\" title=\"\(alt)\" height=\"32\">"
    }
  }

  static func inlineHTML(_ markdown: String, emotes: [String: String] = [:]) -> String {
    guard
      let parsed = try? AttributedString(
        markdown: markdown,
        options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))
    else {
      return replacingEmotes(
        in: escape(markdown).replacingOccurrences(of: "\n", with: "<br>"), emotes: emotes)
    }
    var html = ""
    for run in parsed.runs {
      var piece = escape(String(parsed[run.range].characters))
        .replacingOccurrences(of: "\n", with: "<br>")
      let intent = run.inlinePresentationIntent ?? []
      if !intent.contains(.code) { piece = replacingEmotes(in: piece, emotes: emotes) }
      if intent.contains(.code) { piece = "<code>\(piece)</code>" }
      if intent.contains(.strikethrough) { piece = "<del>\(piece)</del>" }
      if intent.contains(.emphasized) { piece = "<em>\(piece)</em>" }
      if intent.contains(.stronglyEmphasized) { piece = "<strong>\(piece)</strong>" }
      if let link = run.link { piece = "<a href=\"\(escape(link.absoluteString))\">\(piece)</a>" }
      html += piece
    }
    return html
  }

  static func escape(_ text: String) -> String {
    text.replacingOccurrences(of: "&", with: "&amp;")
      .replacingOccurrences(of: "<", with: "&lt;")
      .replacingOccurrences(of: ">", with: "&gt;")
      .replacingOccurrences(of: "\"", with: "&quot;")
  }
}
