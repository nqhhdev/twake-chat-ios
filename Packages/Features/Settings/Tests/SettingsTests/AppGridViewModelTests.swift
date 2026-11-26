import Domain
import Foundation
import Testing

@testable import Settings

@MainActor
struct AppGridViewModelTests {
  @Test func theAppsComeFromTheBuild() async {
    let mail = TwakeApp(
      id: "mail", name: "Twake Mail", url: URL(string: "https://mail.example.org")!,
      symbol: "envelope")
    let model = AppGridViewModel(
      capabilities: FixedCapabilities(value: ServerCapabilities(build: BuildServices(apps: [mail])))
    )
    await model.load()
    #expect(model.apps == [mail])
  }

  @Test func aBuildWithoutAppsShowsNoGrid() async {
    let model = AppGridViewModel(capabilities: FixedCapabilities(value: .none))
    await model.load()
    #expect(model.apps.isEmpty)
  }
}
