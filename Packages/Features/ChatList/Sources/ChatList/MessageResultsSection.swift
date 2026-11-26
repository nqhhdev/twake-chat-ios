import DesignSystem
import Domain
import SwiftUI

struct MessageResultsSection: View {
  let viewModel: ChatListViewModel
  @Environment(\.openURL) private var openURL

  var body: some View {
    if !viewModel.peopleResults.isEmpty {
      Section("People") {
        ForEach(viewModel.peopleResults) { person in
          Button {
            Task { await viewModel.open(person) }
          } label: {
            HStack(spacing: 12) {
              TwakeAvatar(name: person.name, size: 36)
              VStack(alignment: .leading, spacing: 2) {
                Text(person.name).font(.body.weight(.semibold)).lineLimit(1)
                Text(person.id).font(.caption).foregroundStyle(SysColors.textSecondary)
                  .lineLimit(1)
              }
            }
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .transition(.opacity.combined(with: .move(edge: .top)))
        }
      }
    }
    Section {
      if viewModel.isSearchingMessages, viewModel.messageResults.isEmpty {
        HStack {
          Spacer()
          ProgressView()
          Spacer()
        }
      }
      ForEach(viewModel.messageResults) { result in
        Button {
          if let roomId = result.roomId,
            let url = MatrixLink.room(idOrAlias: roomId, eventId: result.eventId, via: []).url
          {
            openURL(url)
          }
        } label: {
          VStack(alignment: .leading, spacing: 3) {
            HStack {
              Text(viewModel.room(of: result)?.name ?? "")
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
              Spacer()
              Text(ChatListViewModel.timeText(result.date))
                .font(.caption)
                .foregroundStyle(SysColors.textSecondary)
            }
            Text("\(Text(result.senderName).bold()): \(result.text)")
              .font(.subheadline)
              .foregroundStyle(SysColors.textSecondary)
              .lineLimit(2)
          }
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .transition(.opacity.combined(with: .move(edge: .top)))
      }
    } header: {
      if viewModel.isSearchingMessages || !viewModel.messageResults.isEmpty {
        Text("Messages")
      }
    } footer: {
      if !viewModel.messageResults.isEmpty {
        Text("Messages in encrypted chats are searched inside each chat.")
      }
    }
  }
}
