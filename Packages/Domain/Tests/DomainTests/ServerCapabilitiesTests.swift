import Domain
import Foundation
import Testing

struct ServerCapabilitiesTests {
  @Test func nothingIsAnnouncedByDefault() {
    let none = ServerCapabilities.none
    #expect(none.tom == nil)
    #expect(none.callFoci.isEmpty)
    #expect(none.supportContact == nil)
    #expect(none.analyticsEndpoint == nil)
    #expect(none.commonSettingsPage(for: "@me:example.org") == nil)
    #expect(!none.supports("org.matrix.msc4140"))
  }

  @Test func theCommonSettingsPageNamesTheUser() {
    let capabilities = ServerCapabilities(
      twakeChat: .init(commonSettingsURL: "https://settings.example.org/{username}/account"))
    #expect(
      capabilities.commonSettingsPage(for: "@alice.b:example.org")?.absoluteString
        == "https://settings.example.org/alice.b/account")
  }

  @Test func aCommonSettingsURLWithoutThePlaceholderOrAnOddUserIsNotUsed() {
    let fixed = ServerCapabilities(
      twakeChat: .init(commonSettingsURL: "https://settings.example.org"))
    #expect(fixed.commonSettingsPage(for: "@alice:example.org") == nil)
    let template = ServerCapabilities(
      twakeChat: .init(commonSettingsURL: "https://settings.example.org/{username}"))
    #expect(template.commonSettingsPage(for: "alice") == nil)
    #expect(template.commonSettingsPage(for: "@al ice:example.org") == nil)
  }

  @Test func aSupportContactMustBeAMatrixId() {
    #expect(
      ServerCapabilities(twakeChat: .init(supportContact: "@support:example.org")).supportContact
        == "@support:example.org")
    #expect(ServerCapabilities(twakeChat: .init(supportContact: "support")).supportContact == nil)
  }

  @Test func analyticsLeaveOnlyWhenTheBuildTurnsThemOn() {
    let side = URL(string: "https://side.example.org")!
    let off = ServerCapabilities(twakeChat: .init(sideService: side))
    #expect(off.analyticsEndpoint == nil)
    let on = ServerCapabilities(
      twakeChat: .init(sideService: side), build: BuildServices(analyticsEnabled: true))
    #expect(on.analyticsEndpoint?.absoluteString == "https://side.example.org/analytics/events")
    let overridden = ServerCapabilities(
      twakeChat: .init(sideService: side),
      build: BuildServices(
        analyticsEnabled: true, analyticsURL: URL(string: "https://a.example.org/events")))
    #expect(overridden.analyticsEndpoint?.absoluteString == "https://a.example.org/events")
    #expect(
      ServerCapabilities(build: BuildServices(analyticsEnabled: true)).analyticsEndpoint == nil)
  }

  @Test func unstableFeaturesAreLookedUpByName() {
    let capabilities = ServerCapabilities(unstableFeatures: ["org.matrix.msc4140"])
    #expect(capabilities.supports("org.matrix.msc4140"))
    #expect(!capabilities.supports("org.matrix.msc3266"))
  }
}
