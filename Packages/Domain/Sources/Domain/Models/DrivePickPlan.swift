import Foundation

public enum DrivePickPlan: Sendable, Equatable {
  case links([String])
  case attach([DriveDocument], skippedShortcuts: Int)
  case shortcutsOnly
  case nothingToSend

  public static let maxMessageLength = 4000

  public static func plan(_ documents: [DriveDocument]) -> DrivePickPlan {
    let shared = documents.filter { $0.sharingLink != nil }
    if !shared.isEmpty {
      let lines = shared.compactMap(linkLine)
      return lines.isEmpty ? .nothingToSend : .links(messages(of: lines))
    }
    let shortcuts = documents.filter(isShortcut).count
    let downloads = documents.filter { !isShortcut($0) && isSafe($0.downloadLink) }
    if !downloads.isEmpty { return .attach(downloads, skippedShortcuts: shortcuts) }
    return shortcuts > 0 ? .shortcutsOnly : .nothingToSend
  }

  static func isShortcut(_ document: DriveDocument) -> Bool {
    document.mimeType == "application/internet-shortcut"
      || document.name.lowercased().hasSuffix(".url")
  }

  static func isSafe(_ url: URL?) -> Bool {
    guard let url, url.scheme?.lowercased() == "https", let host = url.host() else { return false }
    return !host.isEmpty
  }

  static func linkLine(_ document: DriveDocument) -> String? {
    guard let url = document.sharingLink, isSafe(url) else { return nil }
    let address = url.absoluteString
      .replacingOccurrences(of: "(", with: "%28")
      .replacingOccurrences(of: ")", with: "%29")
    let room = maxMessageLength - address.utf16.count - "[]()".utf16.count
    guard room >= 1 else { return nil }
    return "[\(cut(label(of: document.name), to: room))](\(address))"
  }

  static func label(of name: String) -> String {
    name.filter { !"[]\\".contains($0) }
      .split(whereSeparator: \.isNewline)
      .map { $0.trimmingCharacters(in: .whitespaces) }
      .joined(separator: " ")
  }

  static func cut(_ text: String, to length: Int) -> String {
    var kept = String.UnicodeScalarView()
    var used = 0
    for scalar in text.unicodeScalars {
      used += scalar.utf16.count
      if used > length { break }
      kept.append(scalar)
    }
    return String(kept)
  }

  static func messages(of lines: [String], maxLength: Int = maxMessageLength) -> [String] {
    var messages: [String] = []
    var current = ""
    for line in lines {
      let extra = current.isEmpty ? line.utf16.count : line.utf16.count + 1
      if !current.isEmpty, current.utf16.count + extra > maxLength {
        messages.append(current)
        current = ""
      }
      current = current.isEmpty ? line : current + "\n" + line
    }
    if !current.isEmpty { messages.append(current) }
    return messages
  }
}
