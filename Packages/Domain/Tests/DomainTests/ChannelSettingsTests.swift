import Domain
import Foundation
import Testing

struct ChannelSettingsTests {
  @Test func theOwnerInvitesAndHasLevel100() {
    #expect(ChannelSettings.isOwner(canInvite: true, powerLevel: 100))
    #expect(!ChannelSettings.isOwner(canInvite: true, powerLevel: 50))
    #expect(!ChannelSettings.isOwner(canInvite: false, powerLevel: 100))
  }

  @Test func theSwitchReadsTheWebFormat() {
    #expect(ChannelSettings.isEnabled(["enabled": false]) == false)
    #expect(ChannelSettings.isEnabled(["enabled": true]) == true)
    #expect(ChannelSettings.isEnabled([:]) == nil)
    #expect(ChannelSettings.isEnabled(nil) == nil)
    #expect(ChannelSettings.gifsStateType == "app.twake.chat.gifs")
  }
}
