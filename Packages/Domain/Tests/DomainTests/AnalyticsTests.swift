import Domain
import Foundation
import Testing

struct AnalyticsTests {
  struct Capabilities: ServerCapabilitiesRepository {
    let value: ServerCapabilities
    func current() async -> ServerCapabilities { value }
    func refresh() async -> ServerCapabilities { value }
  }

  actor Store: AnalyticsRepository {
    var stored: AnalyticsConsent?
    var sent: [(events: [AnalyticsEvent], endpoint: URL, version: String)] = []

    init(_ stored: AnalyticsConsent? = nil) { self.stored = stored }

    func consent() async -> AnalyticsConsent? { stored }
    func setConsent(_ consent: AnalyticsConsent) async throws(SettingsError) { stored = consent }
    func send(_ events: [AnalyticsEvent], to endpoint: URL, appVersion: String) async -> Bool {
      sent.append((events, endpoint, appVersion))
      return true
    }
  }

  private static let date = Date(timeIntervalSince1970: 1_000)
  private static let on = ServerCapabilities(
    twakeChat: .init(sideService: URL(string: "https://side.example.org")),
    build: BuildServices(analyticsEnabled: true))

  private func makeAnalytics(_ store: Store, _ capabilities: ServerCapabilities = on) -> Analytics {
    Analytics(
      capabilities: Capabilities(value: capabilities), repository: store, appVersion: "1.2",
      now: { Self.date })
  }

  @Test func nothingIsOfferedWhenTheBuildOrTheServerHasNoEndpoint() async {
    #expect(await makeAnalytics(Store(), .none).state() == .unavailable)
    let serverOnly = ServerCapabilities(
      twakeChat: .init(sideService: URL(string: "https://side.example.org")))
    #expect(await makeAnalytics(Store(), serverOnly).state() == .unavailable)
  }

  @Test func theUserIsAskedOnceThenTheChoiceIsKept() async throws {
    let store = Store()
    let analytics = makeAnalytics(store)
    #expect(await analytics.state() == .askConsent)
    try await analytics.setConsent(false)
    #expect(await analytics.state() == .refused)
    #expect(await store.stored == AnalyticsConsent(granted: false, at: Self.date))
  }

  @Test func nothingLeavesBeforeAYesOrAfterANo() async throws {
    let store = Store()
    let analytics = makeAnalytics(store)
    await analytics.track("room_opened")
    await analytics.flush()
    #expect(await store.sent.isEmpty)
    try await analytics.setConsent(false)
    await analytics.startSession()
    await analytics.flush()
    #expect(await store.sent.isEmpty)
  }

  @Test func afterAYesEventsLeaveTogetherToTheEndpoint() async throws {
    let store = Store()
    let analytics = makeAnalytics(store)
    try await analytics.setConsent(true)
    await analytics.startSession()
    await analytics.flush()
    let batch = try #require(await store.sent.first)
    #expect(batch.events.map(\.name) == ["analytics_consent_given", "session_started"])
    #expect(batch.events.first?.properties == ["input": .string("touch")])
    #expect(batch.endpoint.absoluteString == "https://side.example.org/analytics/events")
    #expect(batch.version == "1.2")
    await analytics.flush()
    #expect(await store.sent.count == 1)
  }

  @Test func aConsentGivenOnAnotherDeviceIsRead() async {
    let store = Store(AnalyticsConsent(granted: true, at: Self.date))
    let analytics = makeAnalytics(store)
    await analytics.startSession()
    await analytics.flush()
    #expect(await store.sent.first?.events.map(\.name) == ["session_started"])
  }
}
