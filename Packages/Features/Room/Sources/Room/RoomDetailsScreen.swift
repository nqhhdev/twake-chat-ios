import DesignSystem
import Domain
import SwiftUI

/// The chat details page. It shows the view model's state and forwards taps; it holds no logic.
enum NotificationChoice: Hashable {
  case followDefault
  case mode(NotificationMode)
}

public struct RoomDetailsScreen: View {
  @Bindable var viewModel: RoomDetailsViewModel
  @State private var isConfirmingLeave = false
  @State private var isEditing = false
  @State private var isInviting = false
  @State private var isConfirmingEncryption = false

  public init(viewModel: RoomDetailsViewModel) {
    self.viewModel = viewModel
  }

  private var notificationBinding: Binding<NotificationChoice> {
    Binding {
      if viewModel.followsDefault { return .followDefault }
      return viewModel.notificationMode.map(NotificationChoice.mode) ?? .followDefault
    } set: { choice in
      Task {
        switch choice {
        case .followDefault: await viewModel.setNotificationMode(nil)
        case .mode(let mode): await viewModel.setNotificationMode(mode)
        }
      }
    }
  }

  public var body: some View {
    content
      .background(SysColors.background)
      .navigationTitle("Chat info")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        if case .loaded(let details) = viewModel.state, details.canEdit {
          Button("Edit") { isEditing = true }
        }
      }
      .sheet(isPresented: $isEditing) {
        if case .loaded(let details) = viewModel.state {
          EditRoomSheet(details: details, viewModel: viewModel)
        }
      }
      .sheet(isPresented: $isInviting) {
        if let invitePeople = viewModel.invitePeople {
          invitePeople.view(viewModel.roomId) { Task { await viewModel.load() } }
        }
      }
      .task { await viewModel.load() }
      .task { await viewModel.followChanges() }
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
            TwakeAvatar(
              name: details.name, size: 96, pictureID: details.avatar?.source,
              load: details.avatar.map { reference in
                { @Sendable [viewModel] in await viewModel.picture(reference) }
              })
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
          if details.canEnableEncryption {
            Button {
              isConfirmingEncryption = true
            } label: {
              LabeledContent("Encryption") {
                Text("Turn On").foregroundStyle(SysColors.primary)
              }
            }
            .foregroundStyle(SysColors.onSurface)
          } else {
            LabeledContent("Encryption", value: details.isEncrypted ? "Enabled" : "Not enabled")
          }
          if !details.isDirect {
            LabeledContent("Visibility", value: details.isPublic ? "Public" : "Private")
          }
        }
        if !details.isDirect, details.canChangeAccess, let rule = details.joinRule {
          Section {
            Picker(
              "Who can join",
              selection: Binding(
                get: { rule }, set: { new in Task { await viewModel.setJoinRule(new) } })
            ) {
              Text("Only invited people").tag(RoomDetails.JoinRule.invite)
              Text("Anyone can ask").tag(RoomDetails.JoinRule.knock)
              if !details.isEncrypted || rule == .public {
                Text("Anyone").tag(RoomDetails.JoinRule.public)
              }
            }
          } header: {
            Text("Access")
          } footer: {
            if details.isEncrypted, rule != .public {
              Text("An encrypted chat cannot be opened to anyone.")
            }
          }
        }
        if details.canBan {
          Section {
            NavigationLink {
              BannedMembersScreen(viewModel: viewModel)
            } label: {
              Label("Banned", systemImage: "nosign")
            }
          }
        }
        Section("Notifications") {
          Picker(selection: notificationBinding) {
            Text("Default").tag(NotificationChoice.followDefault)
            Text("All messages").tag(NotificationChoice.mode(.allMessages))
            Text("Mentions and keywords").tag(NotificationChoice.mode(.mentionsAndKeywords))
            Text("Mute").tag(NotificationChoice.mode(.mute))
          } label: {
            Label(
              "Notifications",
              systemImage: viewModel.notificationMode == .mute && !viewModel.followsDefault
                ? "bell.slash" : "bell")
          }
          .disabled(viewModel.notificationMode == nil)
        }
        if let channel = viewModel.channel {
          ChannelSettingsSection(viewModel: viewModel, channel: channel)
        }
        if viewModel.hasContentTabs {
          Section {
            ForEach(RoomContentKind.tabs) { kind in
              // A destination link: this page is itself pushed by `navigationDestination(item:)`, where a value
              // link finds no destination. The tab keeps the first model it is given.
              if let content = viewModel.content(kind) {
                NavigationLink {
                  RoomContentScreen(viewModel: content)
                } label: {
                  Label(kind.title, systemImage: kind.systemImage)
                }
              }
            }
          }
        }
        Section("\(details.joinedMemberCount) members") {
          if details.canInvite, viewModel.invitePeople != nil {
            Button {
              isInviting = true
            } label: {
              Label("Add people", systemImage: "person.badge.plus")
            }
          }
          ForEach(viewModel.filteredMembers) { member in
            NavigationLink {
              MemberProfileScreen(member: member, viewModel: viewModel)
            } label: {
              memberRow(member)
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
        "Turn on encryption?", isPresented: $isConfirmingEncryption, titleVisibility: .visible
      ) {
        Button("Turn On") { Task { await viewModel.enableEncryption() } }
      } message: {
        Text("Messages from now on are end-to-end encrypted. Encryption cannot be turned off.")
      }
      .confirmationDialog(
        "Are you sure you want to leave the chat?", isPresented: $isConfirmingLeave,
        titleVisibility: .visible
      ) {
        Button("Leave", role: .destructive) { Task { await viewModel.leave() } }
      }
    }
  }
}

extension RoomDetailsScreen {
  /// A member: picture, name and Matrix id, with their role or "Invited" on the trailing side.
  func memberRow(_ member: RoomMember) -> some View {
    HStack(spacing: 12) {
      TwakeAvatar(
        name: member.name, size: 40, pictureID: member.avatar?.source,
        load: member.avatar.map { reference in
          { @Sendable [viewModel] in await viewModel.picture(reference) }
        })
      VStack(alignment: .leading, spacing: 0) {
        Text(member.isOwn ? "\(member.name) (you)" : member.name)
          .textStyle(TextStyles.titleMedium)
          .lineLimit(1)
        Text(member.id)
          .textStyle(TextStyles.bodySmall)
          .foregroundStyle(SysColors.textSecondary)
          .lineLimit(1)
      }
      Spacer()
      if member.membership == .invited {
        Text("Invited").textStyle(TextStyles.labelSmall).foregroundStyle(SysColors.textSecondary)
      } else if let role = member.role.label {
        Text(role).textStyle(TextStyles.labelSmall).foregroundStyle(SysColors.textSecondary)
      }
    }
  }
}

/// The room's name and topic, editable, as the Flutter "Edit chat" page; Save sends only what changed.
struct EditRoomSheet: View {
  let viewModel: RoomDetailsViewModel
  @State private var name: String
  @State private var topic: String
  @Environment(\.dismiss) private var dismiss

  init(details: RoomDetails, viewModel: RoomDetailsViewModel) {
    self.viewModel = viewModel
    _name = State(initialValue: details.name)
    _topic = State(initialValue: details.topic ?? "")
  }

  var body: some View {
    NavigationStack {
      Form {
        Section {
          let avatar = viewModel.loadedAvatar
          PhotosAvatarPicker(
            name: name.isEmpty ? "?" : name, pictureID: avatar?.source,
            load: avatar.map { reference in
              { @Sendable [viewModel] in await viewModel.picture(reference) }
            },
            isWorking: viewModel.isUpdatingPicture,
            onPick: { picture in Task { await viewModel.setPicture(picture) } },
            onRemove: avatar == nil ? nil : { Task { await viewModel.removePicture() } }
          )
          .frame(maxWidth: .infinity)
          .listRowBackground(Color.clear)
        }
        Section("Name") {
          TextField("Name", text: $name)
        }
        Section("Description") {
          TextField("Description", text: $topic, axis: .vertical).lineLimit(2...6)
        }
        if let message = viewModel.errorMessage {
          Text(message).foregroundStyle(SysColors.error)
        }
      }
      .navigationTitle("Edit chat")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save") {
            Task { if await viewModel.save(name: name, topic: topic) { dismiss() } }
          }
          .disabled(viewModel.isSaving)
        }
      }
    }
    .presentationDetents([.medium, .large])
  }
}

/// The people banned from a chat, each with Unban.
struct BannedMembersScreen: View {
  let viewModel: RoomDetailsViewModel

  var body: some View {
    Group {
      if let banned = viewModel.banned {
        if banned.isEmpty {
          ContentUnavailableView(
            "Nobody is banned", systemImage: "nosign",
            description: Text("People banned from this chat show here."))
        } else {
          List {
            ForEach(banned) { member in
              HStack(spacing: 12) {
                TwakeAvatar(
                  name: member.name, size: 40, pictureID: member.avatar?.source,
                  load: member.avatar.map { reference in
                    { @Sendable [viewModel] in await viewModel.picture(reference) }
                  })
                VStack(alignment: .leading, spacing: 0) {
                  Text(member.name).lineLimit(1)
                  Text(member.id).font(.footnote).foregroundStyle(SysColors.textSecondary)
                    .lineLimit(1)
                }
                Spacer()
                Button("Unban") { Task { await viewModel.unban(member) } }
                  .buttonStyle(.bordered)
                  .buttonBorderShape(.capsule)
                  .controlSize(.small)
              }
            }
            if let message = viewModel.errorMessage {
              Text(message).foregroundStyle(SysColors.error)
            }
          }
        }
      } else {
        ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
    .navigationTitle("Banned")
    .navigationBarTitleDisplayMode(.inline)
    .task { await viewModel.loadBanned() }
  }
}
