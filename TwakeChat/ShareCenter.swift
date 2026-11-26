import AppShared
import DesignSystem
import Domain
import Observation
import Room
import SwiftUI

/// What other apps share into Twake Chat (Flutter share flow): the share extension leaves the items in the App Group
/// inbox and opens the app with `twake.chat://share`; the shell then asks which chat to send them to, opens it, puts
/// the text in the composer and sends the files.
@MainActor @Observable
final class ShareCenter {
  /// The share waiting for a chat; the shell shows the chat picker while it is set.
  var pending: SharedItems?
  var suggested: SharedItems?

  @ObservationIgnored private let inbox: SharedInbox?

  init(inbox: SharedInbox? = SharedInbox.inAppGroup()) {
    self.inbox = inbox
  }

  /// Reads the share the extension left, if any.
  func load() {
    guard let items = inbox?.pending(), !items.isEmpty else { return }
    if items.roomId != nil {
      pending = nil
      suggested = items
    } else {
      suggested = nil
      pending = items
    }
  }

  /// The share for one chat; its files are deleted once the chat sent them.
  func take() -> IncomingShare? {
    guard let items = pending, let share = share(of: items) else { return nil }
    pending = nil
    return share
  }

  func takeSuggested(for roomId: String) -> IncomingShare? {
    guard let items = suggested, items.roomId == roomId, let share = share(of: items) else {
      return nil
    }
    suggested = nil
    return share
  }

  func pickInstead(of roomId: String) {
    guard var items = suggested, items.roomId == roomId else { return }
    suggested = nil
    items.roomId = nil
    pending = items
  }

  private func share(of items: SharedItems) -> IncomingShare? {
    guard let inbox else { return nil }
    return IncomingShare(
      text: items.text, files: items.files.map(inbox.url(of:)), done: { inbox.clear() })
  }

  /// The user closed the picker: the share is dropped.
  func cancel() {
    pending = nil
    suggested = nil
    inbox?.clear()
  }
}

/// "Send to…": what is being shared, and the chats to pick from, with search, as the iOS share sheet's people row
/// leads to a conversation.
struct ShareTargetSheet: View {
  let items: SharedItems
  let rooms: [RoomSummary]
  let onPick: (RoomSummary) -> Void
  let onCancel: () -> Void
  @State private var query = ""

  var body: some View {
    NavigationStack {
      List {
        Section {
          summary
        }
        Section("Chats") {
          ForEach(filtered) { room in
            Button {
              onPick(room)
            } label: {
              HStack(spacing: 12) {
                TwakeAvatar(name: room.name, size: 40)
                Text(room.name).lineLimit(1)
              }
            }
            .foregroundStyle(SysColors.onSurface)
          }
        }
      }
      .searchable(text: $query, prompt: "Search chats")
      .navigationTitle("Send to")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel", action: onCancel)
        }
        ToolbarItem(placement: .confirmationAction) { AccountSwitcherMenu() }
      }
    }
  }

  private var filtered: [RoomSummary] {
    let text = query.trimmingCharacters(in: .whitespaces)
    guard !text.isEmpty else { return rooms }
    return rooms.filter { $0.name.localizedCaseInsensitiveContains(text) }
  }

  /// "2 pictures, 1 file" and the start of the text.
  @ViewBuilder private var summary: some View {
    let counts = Self.counts(items.files)
    if !counts.isEmpty {
      Label(counts, systemImage: "paperclip")
    }
    if let text = items.text, !text.isEmpty {
      Text(text).lineLimit(3).foregroundStyle(SysColors.textSecondary)
    }
  }

  static func counts(_ files: [SharedItems.File]) -> String {
    let pictures = files.filter { $0.kind == .image }.count
    let videos = files.filter { $0.kind == .video }.count
    let others = files.count - pictures - videos
    return [
      pictures > 0 ? (pictures == 1 ? "1 picture" : "\(pictures) pictures") : nil,
      videos > 0 ? (videos == 1 ? "1 video" : "\(videos) videos") : nil,
      others > 0 ? (others == 1 ? "1 file" : "\(others) files") : nil,
    ].compactMap { $0 }.joined(separator: ", ")
  }
}
