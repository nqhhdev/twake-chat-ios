import DesignSystem
import Domain
import SwiftUI

/// The chat details page. It shows the view model's state and forwards taps; it holds no logic.
public struct RoomDetailsScreen: View {
  @Bindable var viewModel: RoomDetailsViewModel
  @State private var isConfirmingLeave = false

  public init(viewModel: RoomDetailsViewModel) {
    self.viewModel = viewModel
  }

  public var body: some View {
    content
      .background(SysColors.background)
      .navigationTitle("Chat info")
      .navigationBarTitleDisplayMode(.inline)
      .task { await viewModel.load() }
  }

  @ViewBuilder private var content: some View {
    switch viewModel.state {
    case .loading:
      ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
    case .failed(let message):
      ContentUnavailableView(message, systemImage: "exclamationmark.triangle")
    case .loaded(let details):
      List {
        Section {
          VStack(spacing: 8) {
            TwakeAvatar(name: details.name, size: 96)
            Text(details.name).textStyle(TextStyles.headlineSmall).multilineTextAlignment(.center)
            if let topic = details.topic {
              Text(topic)
                .textStyle(TextStyles.bodyMedium)
                .foregroundStyle(SysColors.textSecondary)
                .multilineTextAlignment(.center)
            }
          }
          .frame(maxWidth: .infinity)
          .listRowBackground(Color.clear)
        }
        Section {
          if let alias = details.alias {
            LabeledContent("Address", value: alias)
          }
          LabeledContent("Encryption", value: details.isEncrypted ? "Enabled" : "Not enabled")
          if !details.isDirect {
            LabeledContent("Visibility", value: details.isPublic ? "Public" : "Private")
          }
        }
        Section("\(details.joinedMemberCount) members") {
          ForEach(viewModel.filteredMembers) { member in
            HStack(spacing: 12) {
              TwakeAvatar(name: member.name, size: 40)
              VStack(alignment: .leading, spacing: 0) {
                Text(member.name).textStyle(TextStyles.titleMedium).lineLimit(1)
                Text(member.id)
                  .textStyle(TextStyles.bodySmall)
                  .foregroundStyle(SysColors.textSecondary)
                  .lineLimit(1)
              }
              Spacer()
              if member.membership == .invited {
                Text("Invited").textStyle(TextStyles.labelSmall).foregroundStyle(
                  SysColors.textSecondary)
              }
            }
          }
        }
        Section {
          Button("Leave chat", role: .destructive) { isConfirmingLeave = true }
            .disabled(viewModel.isLeaving)
          if let message = viewModel.errorMessage {
            Text(message).foregroundStyle(SysColors.error)
          }
        }
      }
      .searchable(text: $viewModel.memberQuery, prompt: "Search members")
      .confirmationDialog(
        "Are you sure you want to leave the chat?", isPresented: $isConfirmingLeave,
        titleVisibility: .visible
      ) {
        Button("Leave", role: .destructive) { Task { await viewModel.leave() } }
      }
    }
  }
}
