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

  static func translatedKeys(_ language: String) throws -> Set<String> {
    let data = try Data(contentsOf: sources.appending(path: "Resources/Localizable.xcstrings"))
    let catalog = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    let strings = catalog?["strings"] as? [String: [String: Any]] ?? [:]
    return Set(
      strings.compactMap { key, entry in
        let localizations = entry["localizations"] as? [String: Any]
        return localizations?[language] == nil ? nil : key
      })
  }

  @Test func theSourcesUseLocalizedStrings() throws {
    #expect(try !Self.keysInSources().isEmpty)
  }

  @Test(arguments: ["fr", "vi"])
  func everyKeyInTheCodeIsTranslated(language: String) throws {
    let missing = try Self.keysInSources().subtracting(Self.translatedKeys(language))
    #expect(missing.isEmpty, "Missing in \(language): \(missing.sorted())")
  }
}
