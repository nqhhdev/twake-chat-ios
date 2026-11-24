import DesignSystem
import Domain
import SwiftUI
import UIKit

/// The Meet calls of one room (#92). There is no calling in the app (ADR 0011, ADR 0023): the header button makes a
/// call link, posts it in the room as the Flutter app does and opens it in the browser; a call posted in the room shows
/// as a card that joins it. The room screen offers calls only when the account's server announces a Meet server.
@MainActor @Observable
public final class MeetCallViewModel {
  public let roomId: String
  /// The account's Meet base URL; `nil` until loaded, or when the server has no Meet.
  public private(set) var baseURL: URL?
  public private(set) var isStarting = false
  /// Shown when a call could not be started.
  public var errorMessage: String?

  @ObservationIgnored private let repository: any MeetCallRepository

  public init(roomId: String, repository: any MeetCallRepository) {
    self.roomId = roomId
    self.repository = repository
  }

  public func load() async {
    baseURL = await repository.meetBaseURL()
  }

  /// Starts a call in the room; returns its link to open, or `nil` when none was started.
  public func start() async -> URL? {
    guard let baseURL, !isStarting else { return nil }
    isStarting = true
    defer { isStarting = false }
    do {
      return try await repository.startCall(
        inRoom: roomId, base: baseURL, text: MeetLink.startedTitle)
    } catch MeetCallError.notJoined {
      // The user left the room meanwhile: there is no call to start.
      return nil
    } catch {
      errorMessage = "Failed to start the call"
      return nil
    }
  }

  /// The link to join when a message is a call on the account's Meet server, `nil` otherwise.
  public func link(of call: TimelineMessage.Call?) -> URL? {
    guard case .link(let text)? = call, let baseURL else { return nil }
    return MeetLink.callLink(text, base: baseURL)
  }
}

/// The header button that starts a call and opens it.
struct MeetCallButton: View {
  let calls: MeetCallViewModel
  @Environment(\.openURL) private var openURL

  var body: some View {
    if calls.isStarting {
      ProgressView()
    } else {
      Button("Start video call", systemImage: "video") {
        Task {
          if let link = await calls.start() { openURL(link) }
        }
      }
    }
  }
}

/// A call posted in the room: its title, and buttons to copy its link and to join it.
struct CallLinkCard: View {
  let link: URL
  /// Drawn in the long-press layer: the buttons do nothing there.
  var isPreview = false
  @Environment(\.openURL) private var openURL

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Label(MeetLink.startedTitle, systemImage: "video.fill")
        .textStyle(TextStyles.bodyMedium)
        .foregroundStyle(SysColors.onSurface)
      HStack(spacing: 8) {
        Button("Copy link", systemImage: "doc.on.doc") { UIPasteboard.general.url = link }
          .buttonStyle(.bordered)
        Button("Join call", systemImage: "video") { openURL(link) }
          .buttonStyle(.borderedProminent)
      }
      .controlSize(.small)
      .disabled(isPreview)
    }
  }
}
