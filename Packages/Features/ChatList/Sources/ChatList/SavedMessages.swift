import DesignSystem
import Domain
import SwiftUI

/// The messages the user saved, newest first, shared with the web app: the chat, the sender and a preview. A tap opens
/// the chat at the message; a swipe forgets it.
struct SavedMessagesScreen: View {
  let repository: any SavedMessagesRepository
  @State private var messages: [SavedMessage]?
  @Environment(\.openURL) private var openURL

  var body: some View {
    Group {
      if let messages {
        if messages.isEmpty {
          ContentUnavailableView(
            localized("No saved messages"), systemImage: "bookmark",
            description: Text(localized("Long press a message and choose Save to keep it here.")))
        } else {
          List {
            ForEach(messages) { message in
              Button {
                if let url = MatrixLink.room(
                  idOrAlias: message.ref.roomId, eventId: message.ref.eventId, via: []
                ).url {
                  openURL(url)
                }
              } label: {
                row(message)
              }
              .buttonStyle(.plain)
              .swipeActions {
                Button(localized("Remove"), systemImage: "bookmark.slash", role: .destructive) {
                  Task { await forget(message) }
                }
              }
            }
          }
          .animation(.spring(response: 0.35, dampingFraction: 0.85), value: messages)
        }
      } else {
        ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
    .navigationTitle(localized("Saved messages"))
    .task { messages = await repository.savedMessages() }
    .refreshable { messages = await repository.savedMessages() }
  }

  private func row(_ message: SavedMessage) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack {
        Label(message.roomName, systemImage: "bubble.left.and.bubble.right")
          .font(.footnote.weight(.semibold))
          .foregroundStyle(SysColors.primary)
          .lineLimit(1)
        Spacer()
        if let date = message.date {
          Text(date, format: .dateTime.day().month(.abbreviated).hour().minute())
            .font(.caption)
            .foregroundStyle(SysColors.textSecondary)
        }
      }
      if let sender = message.senderName {
        Text(sender).font(.subheadline.weight(.semibold))
      }
      Text(message.text ?? localized("This message is not available."))
        .font(.subheadline)
        .foregroundStyle(message.text == nil ? SysColors.textSecondary : SysColors.onSurface)
        .lineLimit(3)
    }
    .padding(.vertical, 4)
    .contentShape(Rectangle())
  }

  private func forget(_ message: SavedMessage) async {
    do {
      try await repository.setSaved(false, roomId: message.ref.roomId, eventId: message.ref.eventId)
      messages?.removeAll { $0.id == message.id }
    } catch {}
  }
}
