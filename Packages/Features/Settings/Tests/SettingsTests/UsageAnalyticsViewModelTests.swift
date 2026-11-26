import Domain
import Foundation
import Testing

@testable import Settings

@MainActor
struct UsageAnalyticsViewModelTests {
  actor Store: AnalyticsRepository {
    var stored: AnalyticsConsent?
    var fails = false
    var sentNames: [String] = []

    func consent() async -> AnalyticsConsent? { stored }
    func setConsent(_ consent: AnalyticsConsent) async throws(SettingsError) {
      if fails { throw .requestFailed }
      stored = consent
    }
    func send(_ events: [AnalyticsEvent], to endpoint: URL, appVersion: String) async -> Bool {
      sentNames += events.map(\.name)
      return true
    }
    func failNext() { fails = true }
  }

  private let enabled = ServerCapabilities(
    twakeChat: .init(sideService: URL(string: "https://side.example.org")),
    build: BuildServices(analyticsEnabled: true))

  private func makeModel(_ store: Store, _ capabilities: ServerCapabilities)
    -> UsageAnalyticsViewModel
  {
    UsageAnalyticsViewModel(
      analytics: Analytics(
        capabilities: FixedCapabilities(value: capabilities), repository: store, appVersion: "1"))
  }

  @Test func theUserIsAskedOnceWhenAnalyticsAreOn() async {
    let store = Store()
    let model = makeModel(store, enabled)
    await model.start()
    #expect(model.state == .askConsent)
    #expect(model.isPrompting)
    await model.choose(false)
    #expect(!model.isPrompting)
    #expect(model.state == .refused)
    #expect(await store.stored?.granted == false)
  }

  @Test func nothingIsAskedOrShownWhenTheBuildLeavesAnalyticsOff() async {
    let model = makeModel(Store(), .none)
    await model.start()
    #expect(model.state == .unavailable)
    #expect(!model.isPrompting)
  }

  @Test func aFailedSaveKeepsTheQuestion() async {
    let store = Store()
    await store.failNext()
    let model = makeModel(store, enabled)
    await model.start()
    await model.choose(true)
    #expect(model.isPrompting)
    #expect(model.errorMessage == "Could not save your choice. Please try again.")
    #expect(model.state == .askConsent)
  }
}
