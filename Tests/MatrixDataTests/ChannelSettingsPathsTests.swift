import Domain
import Foundation
import Testing

@testable import MatrixData

struct ChannelSettingsPathsTests {
  @Test func theGifsSwitchIsRoomStateWithAnEmptyStateKey() {
    #expect(
      RoomDetailsProxy.statePath(ChannelSettings.gifsStateType, roomId: "!r:example.org")
        == "rooms/%21r%3Aexample%2Eorg/state/app.twake.chat.gifs/")
  }
}
