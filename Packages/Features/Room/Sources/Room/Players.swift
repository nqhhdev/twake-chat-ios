import AVKit
import DesignSystem
import Domain
import SwiftUI

/// The speeds the audio player's button turns through, in the web client's order.
enum PlaybackSpeed: Float, CaseIterable, Sendable {
  case normal = 1
  case faster = 1.5
  case fastest = 2
  case slower = 0.5

  /// The speed after this one; the last turns back to the first.
  var next: PlaybackSpeed {
    let all = Self.allCases
    let index = all.firstIndex(of: self) ?? 0
    return all[(index + 1) % all.count]
  }

  /// "1×", "1.5×", "2×", "0.5×".
  var label: String { String(format: "%g×", rawValue) }
}

/// The speed every voice and audio message plays at, kept until the app quits so the next message plays at it too.
@MainActor @Observable
final class PlaybackSpeedSetting {
  static let shared = PlaybackSpeedSetting()

  private(set) var speed: PlaybackSpeed = .normal

  func turn() { speed = speed.next }
}

/// A voice message or audio file, played in the bubble as Telegram and iMessage play them: a round play/pause button,
/// bars that fill as it plays and dance while playing, and the time left. The file downloads on the first tap.
struct AudioMessageRow: View {
  let message: TimelineMessage
  let viewModel: RoomViewModel

  @State private var player: AVAudioPlayer?
  @State private var isLoading = false
  @State private var isPlaying = false
  @State private var progress: Double = 0
  @State private var duration: TimeInterval = 0
  private let speedSetting = PlaybackSpeedSetting.shared

  /// Fixed bar heights from the message id, so each message keeps its own shape.
  private var bars: [CGFloat] {
    var seed = UInt64(truncatingIfNeeded: (message.eventId ?? message.senderId).hashValue)
    return (0..<28).map { _ in
      seed = seed &* 6_364_136_223_846_793_005 &+ 1
      return 0.25 + CGFloat(seed >> 33 % 1000) / 1000 * 0.75
    }
  }

  var body: some View {
    HStack(spacing: 10) {
      Button(action: toggle) {
        ZStack {
          Circle().fill(SysColors.primary).frame(width: 40, height: 40)
          if isLoading {
            ProgressView().tint(.white)
          } else {
            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
              .foregroundStyle(.white)
              .contentTransition(.symbolEffect(.replace))
          }
        }
      }
      .buttonStyle(PressScaleButtonStyle())
      .accessibilityLabel(isPlaying ? "Pause" : "Play")
      VStack(alignment: .leading, spacing: 4) {
        TimelineView(.animation(paused: !isPlaying)) { context in
          HStack(spacing: 2) {
            ForEach(bars.indices, id: \.self) { index in
              let played = Double(index) / Double(bars.count) < progress
              let wave =
                isPlaying
                ? 0.85 + 0.15 * sin(context.date.timeIntervalSinceReferenceDate * 8 + Double(index))
                : 1
              Capsule()
                .fill(played ? SysColors.primary : SysColors.outline)
                .frame(width: 3, height: 24 * bars[index] * wave)
            }
          }
          .frame(height: 24)
        }
        Text(Self.time(isPlaying || progress > 0 ? duration * (1 - progress) : duration))
          .textStyle(TextStyles.labelSmall)
          .foregroundStyle(SysColors.textSecondary)
          .monospacedDigit()
      }
      Button(action: turnSpeed) {
        Text(speedSetting.speed.label)
          .textStyle(TextStyles.labelSmall)
          .foregroundStyle(SysColors.primary)
          .monospacedDigit()
          .frame(minWidth: 36, minHeight: 24)
          .background(SysColors.primaryContainer, in: Capsule())
      }
      .buttonStyle(PressScaleButtonStyle())
      .accessibilityLabel("Playback speed")
      .accessibilityValue(speedSetting.speed.label)
    }
    .task(id: isPlaying) {
      // Follows the player while it plays.
      while isPlaying, let player {
        progress = player.duration > 0 ? player.currentTime / player.duration : 0
        if !player.isPlaying {
          isPlaying = false
          progress = 0
        }
        try? await Task.sleep(for: .milliseconds(50))
      }
    }
    .onDisappear { player?.stop() }
  }

  private func toggle() {
    if let player {
      if player.isPlaying {
        player.pause()
        isPlaying = false
      } else {
        // Another message may have changed the speed since this one paused.
        player.rate = speedSetting.speed.rawValue
        player.play()
        isPlaying = true
      }
      return
    }
    Task {
      isLoading = true
      defer { isLoading = false }
      guard let url = await viewModel.file(of: message),
        let loaded = try? AVAudioPlayer(contentsOf: url)
      else { return }
      try? AVAudioSession.sharedInstance().setCategory(.playback)
      loaded.enableRate = true
      loaded.rate = speedSetting.speed.rawValue
      player = loaded
      duration = loaded.duration
      loaded.play()
      isPlaying = true
    }
  }

  private func turnSpeed() {
    speedSetting.turn()
    player?.rate = speedSetting.speed.rawValue
  }

  static func time(_ seconds: TimeInterval) -> String {
    let total = max(0, Int(seconds.rounded()))
    return String(format: "%d:%02d", total / 60, total % 60)
  }
}

/// A video full screen with the system player, after it downloads.
struct VideoPlayerScreen: View {
  let url: URL
  @Environment(\.dismiss) private var dismiss
  @State private var player: AVPlayer?

  var body: some View {
    ZStack(alignment: .topLeading) {
      Color.black.ignoresSafeArea()
      if let player {
        VideoPlayer(player: player).ignoresSafeArea()
      }
      Button {
        dismiss()
      } label: {
        Image(systemName: "xmark")
          .font(.system(size: 16, weight: .semibold))
          .foregroundStyle(.white)
          .frame(width: 40, height: 40)
          .background(.black.opacity(0.5), in: Circle())
      }
      .accessibilityLabel("Close")
      .padding(16)
    }
    .onAppear {
      try? AVAudioSession.sharedInstance().setCategory(.playback)
      let player = AVPlayer(url: url)
      self.player = player
      player.play()
    }
    .onDisappear { player?.pause() }
  }
}
