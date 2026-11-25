import Domain
import Foundation
import Testing

@testable import TwakeChat

@MainActor
struct PushCenterTests {
  private actor RecordingPush: PushRepository {
    private(set) var registered: [(Data, Bool)] = []
    private(set) var unregisterCount = 0

    func register(deviceToken: Data, isProduction: Bool) async throws(PushError) {
      registered.append((deviceToken, isProduction))
    }

    func unregister() async { unregisterCount += 1 }
  }

  @Test func allowedNotificationsAskAppleForAToken() async {
    var asked = 0
    let center = PushCenter(
      repository: RecordingPush(), requestAuthorization: { true },
      registerForRemoteNotifications: { asked += 1 })
    await center.start()
    #expect(center.isAllowed == true)
    #expect(asked == 1)
  }

  @Test func refusedNotificationsDoNotRegister() async {
    var asked = 0
    let center = PushCenter(
      repository: RecordingPush(), requestAuthorization: { false },
      registerForRemoteNotifications: { asked += 1 })
    await center.start()
    #expect(center.isAllowed == false)
    #expect(asked == 0)
  }

  @Test func theTokenGoesToTheSandboxInDebugAndLogoutRemovesIt() async {
    let push = RecordingPush()
    let center = PushCenter(repository: push, requestAuthorization: { true })
    await center.didReceive(deviceToken: Data([1, 2, 3]))
    let registered = await push.registered
    #expect(registered.map(\.0) == [Data([1, 2, 3])])
    #expect(registered.first?.1 == false)
    await center.stop()
    #expect(await push.unregisterCount == 1)
  }

  @Test func withoutARepositoryNothingIsAsked() async {
    var asked = 0
    let center = PushCenter(
      repository: nil,
      requestAuthorization: {
        asked += 1
        return true
      })
    await center.start()
    #expect(asked == 0)
    #expect(center.isAllowed == nil)
  }

  @Test func theSigningProfileDecidesTheApnsServer() {
    func profile(_ entitlements: String) -> Data {
      Data(
        "\u{30}\u{82}signed<plist><dict><key>Entitlements</key><dict>\(entitlements)</dict></dict></plist>"
          .utf8)
    }
    let development = profile("<key>aps-environment</key>\n\t<string>development</string>")
    let production = profile("<key>aps-environment</key><string>production</string>")
    #expect(!ApnsEnvironment.isProduction(profile: development, isSimulator: false))
    #expect(ApnsEnvironment.isProduction(profile: production, isSimulator: false))
    #expect(ApnsEnvironment.isProduction(profile: profile(""), isSimulator: false))
    #expect(ApnsEnvironment.isProduction(profile: nil, isSimulator: false))
    #expect(!ApnsEnvironment.isProduction(profile: nil, isSimulator: true))
  }
}
