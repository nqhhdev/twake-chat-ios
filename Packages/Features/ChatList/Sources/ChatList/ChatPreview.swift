import DesignSystem
import Domain
import Observation
import SwiftUI

/// A chat's latest messages, read-only, for the preview a long press on its row shows above the menu, as iMessage
/// does. It follows the room's timeline while the preview is shown and closes it when the preview goes away. It never
/// marks the chat as read: it sends no read receipt and does not change the unread state.
@MainActor @Observable
public final class ChatPreviewViewModel {
  /// How many of the latest messages the preview shows.
  static let limit = 6

  /// One message as the preview shows it.
  public struct Line: Identifiable, Equatable, Sendable {
    public let id: String
    public let senderName: String
    public let isOwn: Bool
    public let text: String
    /// Shown before the text for a picture, a file, a deleted or an encrypted message; `nil` for plain text.
    public let systemImage: String?
    /// A deleted or an undecryptable message, shown greyed as the timeline shows it.
    public let isPlaceholder: Bool
  }

  public enum State: Equatable {
    case loading
    /// The latest messages, newest last; empty when the room has none yet.
    case loaded([Line])
    case failed
  }

  public let room: RoomSummary
  public private(set) var state: State = .loading
  @ObservationIgnored private let repository: any TimelineRepository

  init(room: RoomSummary, repository: any TimelineRepository) {
    self.room = room
    self.repository = repository
  }

  /// Follows the timeline until the calling task is cancelled (the preview closes) or the timeline ends, then closes
  /// it. When the first items hold fewer messages than the preview shows, one older page is loaded.
  public func run() async {
    let items: AsyncStream<[TimelineItem]>
    do {
      items = try await repository.open()
    } catch {
      state = .failed
      await repository.close()
      return
    }
    var older: Task<Void, Never>?
    for await list in items {
      // The timeline publishes an empty list before the SDK's first items.
      guard !list.isEmpty else { continue }
      let lines = Self.lines(list)
      state = .loaded(lines)
      if older == nil, lines.count < Self.limit,
        !list.contains(where: { $0.kind == .timelineStart })
      {
        older = Task { [repository] in _ = try? await repository.loadOlder() }
      }
    }
    older?.cancel()
    await repository.close()
  }

  /// The latest messages of `items`, newest last. Room events and hidden events are left out.
  static func lines(_ items: [TimelineItem]) -> [Line] {
    let messages = items.compactMap { item -> Line? in
      guard item.visibility == .always, case .message(let message) = item.kind else { return nil }
      return line(id: item.id, message)
    }
    return Array(messages.suffix(limit))
  }

  private static func line(id: String, _ message: TimelineMessage) -> Line {
    // The wording of the timeline's message bodies, so the preview reads as the chat does.
    let (text, image, isPlaceholder): (String, String?, Bool) =
      switch message.body {
      case .text(let text), .notice(let text), .sticker(let text): (text, nil, false)
      case .emote(let text): ("\(message.senderName) \(text)", nil, false)
      case .image(let caption): (caption ?? "Picture", "photo", false)
      case .video(let caption): (caption ?? "Video", "video", false)
      case .audio(let caption): (caption ?? "Audio", "waveform", false)
      case .file(let name): (name, "doc", false)
      case .location(let text, _): (text, "mappin.and.ellipse", false)
      case .poll(let question): (question, "chart.bar", false)
      case .redacted: ("This message has been deleted", "trash", true)
      case .unableToDecrypt:
        ("This message cannot be read on this device yet.", "lock.badge.clock", true)
      case .unsupported: ("Unknown event", nil, true)
      }
    return Line(
      id: id, senderName: message.senderName, isOwn: message.isOwn, text: text,
      systemImage: image, isPlaceholder: isPlaceholder)
  }
}

/// The preview above a chat row's long-press menu: the chat's picture and name, then its latest messages as bubbles,
/// newest at the bottom. The model is made when the preview appears, so the timeline opens only while it is shown.
struct ChatPreview: View {
  let room: RoomSummary
  let viewModel: ChatListViewModel
  let make: @MainActor () -> ChatPreviewViewModel?
  @State private var model: ChatPreviewViewModel?

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 10) {
        RoomAvatar(room: room, viewModel: viewModel, size: 36)
        Text(room.name)
          .textStyle(TextStyles.titleMedium)
          .foregroundStyle(SysColors.onSurface)
          .lineLimit(1)
        Spacer(minLength: 0)
      }
      .padding(12)
      Divider()
      messages
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .bottom)
        .padding(12)
    }
    .frame(width: 320)
    .background(SysColors.background)
    .task {
      guard let model = make() else { return }
      self.model = model
      await model.run()
    }
  }

  @ViewBuilder private var messages: some View {
    switch model?.state ?? .loading {
    case .loading:
      ProgressView()
    case .failed:
      Text("The messages could not be loaded.")
        .foregroundStyle(SysColors.textSecondary)
    case .loaded(let lines) where lines.isEmpty:
      Text("No messages yet.")
        .foregroundStyle(SysColors.textSecondary)
    case .loaded(let lines):
      VStack(spacing: 6) {
        ForEach(lines) { line in bubble(line) }
      }
    }
  }

  private func bubble(_ line: ChatPreviewViewModel.Line) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      if !line.isOwn && !room.isDirect {
        Text(line.senderName)
          .textStyle(TextStyles.labelMedium)
          .foregroundStyle(SysColors.primary)
          .lineLimit(1)
      }
      Group {
        if let image = line.systemImage {
          Label(line.text, systemImage: image)
        } else {
          Text(line.text)
        }
      }
      .textStyle(TextStyles.bodyMedium)
      .foregroundStyle(line.isPlaceholder ? SysColors.textSecondary : SysColors.onSurface)
      .lineLimit(3)
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 6)
    .background(
      line.isOwn ? SysColors.primaryContainer : SysColors.onPrimary,
      in: RoundedRectangle(cornerRadius: 16)
    )
    .frame(maxWidth: 260, alignment: line.isOwn ? .trailing : .leading)
    .frame(maxWidth: .infinity, alignment: line.isOwn ? .trailing : .leading)
  }
}

/// A chat row's long-press menu, with the chat's preview above it when the chat has one (not a space or an invitation).
struct RoomContextMenu<Menu: View>: ViewModifier {
  let room: RoomSummary
  let viewModel: ChatListViewModel
  @ViewBuilder let menu: () -> Menu
  let hasPreview: Bool

  func body(content: Content) -> some View {
    if hasPreview {
      content.contextMenu {
        menu()
      } preview: {
        ChatPreview(room: room, viewModel: viewModel) { [viewModel, room] in
          viewModel.makePreview(room)
        }
      }
    } else {
      content.contextMenu { menu() }
    }
  }
}
