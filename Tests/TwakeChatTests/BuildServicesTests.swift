import Domain
import Foundation
import Testing

@testable import TwakeChat

struct BuildServicesTests {
  @Test func theBundledTwakeAppsAreRead() {
    let apps = BuildServices.apps(named: "TwakeApps", in: Bundle(for: AppDelegate.self))
    #expect(apps.map(\.name) == ["Twake Mail", "Twake Drive"])
    #expect(apps.allSatisfy { $0.url.scheme == "https" })
  }

  @Test func aMissingListIsEmpty() {
    #expect(BuildServices.apps(named: "Nothing", in: Bundle(for: AppDelegate.self)).isEmpty)
  }

  @Test func theAppBuildLeavesAnalyticsOffAndSetsHelpAndApps() {
    let build = BuildServices.from(Bundle(for: AppDelegate.self))
    #expect(!build.analyticsEnabled)
    #expect(build.supportURL?.absoluteString == "https://twake.app/support")
    #expect(build.apps.count == 2)
  }
}
