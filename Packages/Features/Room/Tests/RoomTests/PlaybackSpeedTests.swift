import Testing

@testable import Room

/// The speed button turns through the web client's speeds, and the chosen speed stays for the next message.
@MainActor
struct PlaybackSpeedTests {
  @Test func theButtonTurnsThroughTheWebSpeedsAndBackToNormal() {
    var speed = PlaybackSpeed.normal
    var seen: [Float] = []
    for _ in 0..<5 {
      seen.append(speed.rawValue)
      speed = speed.next
    }
    #expect(seen == [1, 1.5, 2, 0.5, 1])
  }

  @Test func eachSpeedShowsItsFactor() {
    #expect(PlaybackSpeed.allCases.map(\.label) == ["1×", "1.5×", "2×", "0.5×"])
  }

  @Test func theChosenSpeedStaysUntilTurnedAgain() {
    let setting = PlaybackSpeedSetting()
    #expect(setting.speed == .normal)
    setting.turn()
    #expect(setting.speed == .faster)
    // The next message reads the same setting, so it starts at 1.5×.
    #expect(setting.speed.rawValue == 1.5)
    setting.turn()
    setting.turn()
    setting.turn()
    #expect(setting.speed == .normal)
  }
}
