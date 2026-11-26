import Domain
import Foundation

extension BuildServices {
  static func from(_ bundle: Bundle) -> BuildServices {
    func string(_ key: String) -> String? {
      (bundle.object(forInfoDictionaryKey: key) as? String).flatMap { $0.isEmpty ? nil : $0 }
    }
    return BuildServices(
      supportURL: string("SupportURL").flatMap(URL.init(string:)),
      analyticsEnabled: string("AnalyticsEnabled") == "YES",
      analyticsURL: string("AnalyticsURL").flatMap(URL.init(string:)),
      apps: string("AppGridFile").map { apps(named: $0, in: bundle) } ?? [])
  }

  static func apps(named name: String, in bundle: Bundle) -> [TwakeApp] {
    guard let url = bundle.url(forResource: name, withExtension: "json"),
      let data = try? Data(contentsOf: url)
    else { return [] }
    return (try? JSONDecoder().decode([TwakeApp].self, from: data)) ?? []
  }
}
