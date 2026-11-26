import Foundation
import Testing

@testable import MatrixData

struct LocalizationTests {
  static let sources = URL(filePath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .appending(path: "Packages/MatrixData/Sources/MatrixData")

  static func keysInSources() throws -> Set<String> {
    let files = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)
    var keys = Set<String>()
    while let file = files?.nextObject() as? URL {
      guard file.pathExtension == "swift" else { continue }
      let text = try String(contentsOf: file, encoding: .utf8)
      for match in text.matches(of: /localized\("((?:[^"\\]|\\.)*)"\)/) {
        keys.insert(catalogKey(String(match.output.1)))
      }
    }
    return keys
  }

  static func catalogKey(_ literal: String) -> String {
    var key = ""
    var depth = 0
    var index = literal.startIndex
    while index < literal.endIndex {
      let character = literal[index]
      let next = literal.index(after: index)
      if depth == 0, character == "\\", next < literal.endIndex, literal[next] == "(" {
        key += "%@"
        depth = 1
        index = literal.index(after: next)
        continue
      }
      if depth > 0 {
        if character == "(" { depth += 1 }
        if character == ")" { depth -= 1 }
      } else {
        key.append(character)
      }
      index = next
    }
    return key
  }

  static func table(_ language: String) -> Bundle? {
    Localization.bundle.path(forResource: language, ofType: "lproj").flatMap(Bundle.init(path:))
  }

  @Test func anInterpolationBecomesAStringSpecifier() {
    #expect(Self.catalogKey(#"\(a) changed it to: \(text(b))"#) == "%@ changed it to: %@")
  }

  @Test func theSourcesUseLocalizedStrings() throws {
    #expect(try !Self.keysInSources().isEmpty)
  }

  @Test(arguments: ["fr", "vi"])
  func everyKeyInTheCodeIsTranslated(language: String) throws {
    let table = try #require(Self.table(language))
    let missing = try Self.keysInSources().filter {
      table.localizedString(forKey: $0, value: "\u{1}", table: nil) == "\u{1}"
    }
    #expect(missing.isEmpty, "Missing in \(language): \(missing.sorted())")
  }
}
