import Domain
import Foundation
import Testing

struct VoiceWaveformTests {
  @Test func msc1767AmplitudesFrom0To1024BecomeFractions() {
    #expect(TimelineMessage.Voice.waveform(amplitudes: [0, 256, 512, 1024]) == [0, 0.25, 0.5, 1])
  }

  @Test func amplitudesAboveTheMaximumAreCapped() {
    #expect(TimelineMessage.Voice.waveform(amplitudes: [4096, UInt16.max]) == [1, 1])
  }

  @Test func barsKeepTheLoudestSampleOfEachSlice() {
    let voice = TimelineMessage.Voice(duration: 3, waveform: [0.1, 0.9, 0.2, 0.4, 0.3, 0.8])
    #expect(voice.bars(3) == [0.9, 0.4, 0.8])
  }

  @Test func aShortWaveformIsStretchedOverTheBars() {
    let voice = TimelineMessage.Voice(duration: 1, waveform: [0.2, 0.6])
    #expect(voice.bars(4) == [0.2, 0.2, 0.6, 0.6])
  }

  @Test func noWaveformMeansNoBars() {
    #expect(TimelineMessage.Voice(duration: 2, waveform: []).bars(28).isEmpty)
    #expect(TimelineMessage.Voice(duration: 2, waveform: [0.5]).bars(0).isEmpty)
  }
}
