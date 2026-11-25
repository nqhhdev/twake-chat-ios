import DesignSystem
import Domain
import SwiftUI

/// The Telegram-style bar under the header with the pinned message: a bar per pin on the left (the current one
/// filled), "Pinned message" and its preview. A tap shows the pin before; the text slides as it changes.
struct PinnedBanner: View {
  let viewModel: RoomViewModel

  var body: some View {
    if let message = viewModel.currentPinned {
      Button {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
          viewModel.showPreviousPinned()
        }
      } label: {
        HStack(spacing: 10) {
          VStack(spacing: 2) {
            ForEach(viewModel.pinned.indices, id: \.self) { index in
              Capsule()
                .fill(SysColors.primary.opacity(index == viewModel.pinnedIndex ? 1 : 0.3))
                .frame(width: 3)
            }
          }
          .frame(height: 34)
          VStack(alignment: .leading, spacing: 0) {
            Text(
              viewModel.pinned.count > 1
                ? "Pinned message #\(viewModel.pinnedIndex + 1)" : "Pinned message"
            )
            .textStyle(TextStyles.labelMedium)
            .foregroundStyle(SysColors.primary)
            .contentTransition(.numericText(value: Double(viewModel.pinnedIndex)))
            Text(RoomViewModel.text(of: message.body) ?? RoomViewModel.fileName(of: message))
              .textStyle(TextStyles.bodySmall)
              .foregroundStyle(SysColors.onSurface)
              .lineLimit(1)
              .id(message.eventId)
              .transition(.push(from: .bottom))
          }
          Spacer()
          Image(systemName: "pin.fill").foregroundStyle(SysColors.textSecondary).rotationEffect(
            .degrees(45))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(.bar)
        .overlay(alignment: .bottom) { Rectangle().fill(SysColors.surface).frame(height: 1) }
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .transition(.move(edge: .top).combined(with: .opacity))
      .accessibilityLabel("Pinned message")
    }
  }
}

/// A short confirmation that drops in from the top and fades away.
struct Toast: View {
  let text: String
  var systemImage = "checkmark.circle.fill"

  var body: some View {
    Label(text, systemImage: systemImage)
      .textStyle(TextStyles.labelLarge)
      .foregroundStyle(.white)
      .padding(.horizontal, 16)
      .padding(.vertical, 10)
      .background(.black.opacity(0.75), in: Capsule())
      .padding(.top, 8)
      .transition(.move(edge: .top).combined(with: .opacity))
  }
}

/// Pick a chat to forward a message to, with a search over the chat list.
struct ForwardSheet: View {
  let messages: [TimelineMessage]
  let viewModel: RoomViewModel

  @Environment(\.dismiss) private var dismiss
  @State private var query = ""

  private var rooms: [RoomSummary] {
    let all = viewModel.forwardTargets()
    let text = query.trimmingCharacters(in: .whitespaces)
    return text.isEmpty ? all : all.filter { $0.name.localizedCaseInsensitiveContains(text) }
  }

  var body: some View {
    NavigationStack {
      List(rooms) { room in
        Button {
          Task {
            await viewModel.forward(messages, to: room)
            dismiss()
          }
        } label: {
          HStack(spacing: 12) {
            TwakeAvatar(name: room.name, size: 40)
            Text(room.name).textStyle(TextStyles.titleMedium).foregroundStyle(SysColors.onSurface)
              .lineLimit(1)
          }
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
      }
      .overlay {
        if rooms.isEmpty { ContentUnavailableView.search(text: query) }
      }
      .searchable(
        text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search"
      )
      .twakeTitle("Forward to")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
      }
    }
    .presentationDetents([.medium, .large])
  }
}

/// The people who reacted with one emoji, or who have seen a message, by name when they are room members.
struct PeopleListSheet: View {
  let sheet: RoomViewModel.PeopleSheet
  let viewModel: RoomViewModel
  @State private var members: [String: RoomMember] = [:]

  var body: some View {
    NavigationStack {
      List(sheet.userIds, id: \.self) { userId in
        let member = members[userId]
        HStack(spacing: 12) {
          TwakeAvatar(
            name: member?.name ?? userId, size: 36, pictureID: member?.avatar?.source,
            load: member?.avatar.map { reference in
              { @Sendable [viewModel] in await viewModel.picture(reference) }
            })
          VStack(alignment: .leading, spacing: 0) {
            Text(member?.name ?? userId).lineLimit(1)
            if member?.displayName != nil {
              Text(userId).font(.footnote).foregroundStyle(SysColors.textSecondary).lineLimit(1)
            }
          }
        }
      }
      .overlay {
        if sheet.userIds.isEmpty {
          ContentUnavailableView("No one yet", systemImage: "person.2")
        }
      }
      .navigationTitle(sheet.title)
      .navigationBarTitleDisplayMode(.inline)
    }
    .presentationDetents([.medium, .large])
    .task {
      let list = await viewModel.roomMembers()
      members = Dictionary(list.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }
  }
}

/// All the pinned messages, newest pin first; a tap shows the message in the chat.
struct PinnedListSheet: View {
  let viewModel: RoomViewModel
  let open: (String) -> Void

  var body: some View {
    NavigationStack {
      List(viewModel.pinned.reversed(), id: \.eventId) { message in
        Button {
          if let eventId = message.eventId { open(eventId) }
        } label: {
          VStack(alignment: .leading, spacing: 2) {
            Text(message.senderName).font(.subheadline.weight(.semibold))
            Text(RoomViewModel.text(of: message.body) ?? "Attachment")
              .lineLimit(2)
              .foregroundStyle(SysColors.textSecondary)
          }
        }
        .swipeActions {
          Button("Unpin", systemImage: "pin.slash") {
            Task { await viewModel.togglePin(message) }
          }
        }
      }
      .navigationTitle("Pinned messages")
      .navigationBarTitleDisplayMode(.inline)
    }
    .presentationDetents([.medium, .large])
  }
}

/// Every version of an edited message, the original first, each with its time (web Phase 2b « Edit history »). An
/// encrypted chat cannot show them: the server holds the edits encrypted.
struct EditHistorySheet: View {
  let message: TimelineMessage
  let viewModel: RoomViewModel
  @State private var versions: [MessageVersion]??
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      Group {
        switch versions {
        case .none:
          ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        case .some(.none):
          ContentUnavailableView(
            "Not available", systemImage: "lock",
            description: Text("The edit history of an encrypted chat cannot be shown."))
        case .some(.some(let list)):
          List(Array(list.enumerated()), id: \.element.id) { index, version in
            VStack(alignment: .leading, spacing: 4) {
              Text(index == 0 ? "Original" : "Edit \(index)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(
                  index == list.count - 1 ? SysColors.primary : SysColors.textSecondary)
              Text(version.text)
              Text(version.date, format: .dateTime.day().month(.abbreviated).hour().minute())
                .font(.caption2)
                .foregroundStyle(SysColors.textSecondary)
            }
            .padding(.vertical, 2)
          }
        }
      }
      .twakeTitle("Edit History")
      .toolbar {
        ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
      }
    }
    .presentationDetents([.medium, .large])
    .task {
      let found = await viewModel.editHistory(of: message)
      withAnimation(.easeInOut) { versions = .some(found) }
    }
  }
}

/// A message's details, as the Flutter app's `EventInfoDialog` lists them: who sent it, when, what kind of message it
/// is, and its event id, which a support request or a bug report can quote. The id can be selected and copied.
struct MessageInfoSheet: View {
  let message: TimelineMessage
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      List {
        LabeledContent("Sender") {
          VStack(alignment: .trailing, spacing: 2) {
            Text(message.senderName)
            if message.senderName != message.senderId {
              Text(message.senderId).font(.caption).foregroundStyle(SysColors.textSecondary)
            }
          }
        }
        LabeledContent("Sent") {
          Text(message.date, format: .dateTime.day().month(.wide).year().hour().minute().second())
        }
        LabeledContent("Type", value: Self.kind(of: message.body))
        if message.isEdited { LabeledContent("Edited", value: "Yes") }
        if let eventId = message.eventId {
          Section("Event ID") {
            Text(eventId).font(.footnote.monospaced()).textSelection(.enabled)
          }
        }
      }
      .twakeTitle("Message Info")
      .toolbar {
        ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
      }
    }
    .presentationDetents([.medium, .large])
  }

  /// What kind of message it is, in words.
  static func kind(of body: TimelineMessage.Body) -> String {
    switch body {
    case .text: "Text"
    case .emote: "Emote"
    case .notice: "Notice"
    case .image: "Picture"
    case .video: "Video"
    case .audio: "Audio"
    case .file: "File"
    case .location: "Location"
    case .sticker: "Sticker"
    case .poll: "Poll"
    case .redacted: "Deleted message"
    case .unableToDecrypt: "Encrypted message"
    case .unsupported: "Unsupported message"
    }
  }
}
