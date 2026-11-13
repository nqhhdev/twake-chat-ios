import AVFoundation
import Foundation
import Observation

/// Records a voice message as Telegram does: it starts when the mic button is pressed and stops when it is released,
/// sampling the loudness for the waveform. The file is AAC in a temporary folder. Nothing here logs.
@MainActor @Observable
final class VoiceRecorder {
  struct Recording {
    let url: URL
    let duration: TimeInterval
    let waveform: [Float]
  }

  private(set) var isRecording = false
  private(set) var elapsed: TimeInterval = 0
  /// The latest loudness, 0…1, for the pulsing dot.
  private(set) var level: Float = 0
  private(set) var permissionDenied = false

  @ObservationIgnored private var recorder: AVAudioRecorder?
  @ObservationIgnored private var samples: [Float] = []
  @ObservationIgnored private var meter: Task<Void, Never>?

  /// Recordings shorter than this are dropped, as an accidental tap.
  static let minimumDuration: TimeInterval = 0.8

  func start() async {
    guard !isRecording else { return }
    guard await AVAudioApplication.requestRecordPermission() else {
      permissionDenied = true
      return
    }
    let session = AVAudioSession.sharedInstance()
    do {
      try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
      try session.setActive(true)
      let folder = FileManager.default.temporaryDirectory.appending(
        path: "voice/\(UUID().uuidString)")
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      let recorder = try AVAudioRecorder(
        url: folder.appending(path: "Voice message.m4a"),
        settings: [
          AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44_100, AVNumberOfChannelsKey: 1,
          AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ])
      recorder.isMeteringEnabled = true
      guard recorder.record() else { return }
      self.recorder = recorder
      samples = []
      elapsed = 0
      isRecording = true
      meter = Task { [weak self] in
        while let self, self.isRecording, let recorder = self.recorder {
          recorder.updateMeters()
          // -50 dB and below is silence; 0 dB is the loudest.
          let power = recorder.averagePower(forChannel: 0)
          let normalized = max(0, min(1, (power + 50) / 50))
          self.level = normalized
          self.samples.append(normalized)
          self.elapsed = recorder.currentTime
          try? await Task.sleep(for: .milliseconds(100))
        }
      }
    } catch {
      isRecording = false
    }
  }

  /// Stops and returns the recording, or `nil` when it was too short or cancelled.
  func stop(keep: Bool) -> Recording? {
    guard isRecording, let recorder else { return nil }
    let duration = recorder.currentTime
    recorder.stop()
    meter?.cancel()
    isRecording = false
    self.recorder = nil
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    guard keep, duration >= Self.minimumDuration else {
      try? FileManager.default.removeItem(at: recorder.url.deletingLastPathComponent())
      return nil
    }
    return Recording(
      url: recorder.url, duration: duration, waveform: Self.downsample(samples, to: 100))
  }

  /// The waveform the Matrix voice message carries: at most `count` samples, each the loudest of its slice.
  static func downsample(_ samples: [Float], to count: Int) -> [Float] {
    guard samples.count > count else { return samples }
    let size = Double(samples.count) / Double(count)
    return (0..<count).map { index in
      let lower = Int(Double(index) * size)
      let upper = min(samples.count, Int(Double(index + 1) * size))
      return samples[lower..<max(upper, lower + 1)].max() ?? 0
    }
  }
}
