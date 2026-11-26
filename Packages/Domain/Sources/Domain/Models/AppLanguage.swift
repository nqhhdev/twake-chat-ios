import Foundation

public enum AppLanguage {
  public enum Decision: Sendable, Equatable {
    case keep
    case use(String)
    case followDevice
  }

  public static func decide(
    serverLanguage: String?, available: [String], appliedByApp: String?
  ) -> Decision {
    let offered = Set(available.map(code).filter { $0 != "base" })
    if let language = serverLanguage.map(code), offered.contains(language) {
      return language == appliedByApp ? .keep : .use(language)
    }
    return appliedByApp == nil ? .keep : .followDevice
  }

  static func code(_ identifier: String) -> String {
    let lowered = identifier.lowercased()
    let end = lowered.firstIndex { $0 == "-" || $0 == "_" } ?? lowered.endIndex
    return String(lowered[..<end])
  }
}
