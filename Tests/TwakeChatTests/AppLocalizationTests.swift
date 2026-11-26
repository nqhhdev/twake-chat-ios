import Foundation
import Testing

struct AppLocalizationTests {
  static let catalog = URL(filePath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .appending(path: "TwakeChat/Localizable.xcstrings")

  static func catalogKeys() throws -> [String] {
    let data = try Data(contentsOf: catalog)
    let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    let strings = object?["strings"] as? [String: Any] ?? [:]
    return strings.keys.sorted()
  }

  static func table(_ language: String) -> Bundle? {
    Bundle.main.path(forResource: language, ofType: "lproj").flatMap(Bundle.init(path:))
  }

  @Test func theAppOffersEnglishFrenchAndVietnamese() {
    #expect(Set(Bundle.main.localizations).isSuperset(of: ["en", "fr", "vi"]))
  }

  @Test func theCatalogHasTheEncryptedPushKey() throws {
    #expect(try Self.catalogKeys().contains("newMessageInTwake"))
  }

  @Test(arguments: ["fr", "vi"])
  func everyCatalogKeyIsTranslated(language: String) throws {
    let table = try #require(Self.table(language))
    let missing = try Self.catalogKeys().filter {
      table.localizedString(forKey: $0, value: "\u{1}", table: nil) == "\u{1}"
    }
    #expect(missing.isEmpty, "Missing in \(language): \(missing.sorted())")
  }
}
