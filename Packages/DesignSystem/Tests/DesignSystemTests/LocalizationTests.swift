import Foundation
import Testing

@testable import DesignSystem

struct LocalizationTests {
  static let sources = URL(filePath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .appending(path: "Sources/DesignSystem")

  static func keysInSources() throws -> Set<String> {
    let files = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)
    var keys = Set<String>()
    while let file = files?.nextObject() as? URL {
      guard file.pathExtension == "swift" else { continue }
      let text = try String(contentsOf: file, encoding: .utf8)
      for match in text.matches(of: /localized\("((?:[^"\\]|\\.)*)"/) {
        let key = String(match.output.1)
        if !key.contains("\\") { keys.insert(key) }
      }
    }
    return keys
  }

  static func table(_ language: String) -> Bundle? {
    Localization.bundle.path(forResource: language, ofType: "lproj").flatMap(Bundle.init(path:))
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
