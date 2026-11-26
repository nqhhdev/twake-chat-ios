import DesignSystem
import Domain
import SwiftUI

/// The search field and results shared by the new chat sheet and the Contacts tab.
struct PeopleSearchList: View {
  @Bindable var viewModel: PeopleSearchViewModel
  var phoneContacts: PhoneContactsViewModel?
  var twakeContacts: TwakeContactsViewModel?

  var body: some View {
    list
      .sheet(
        isPresented: Binding(
          get: { viewModel.consent != nil }, set: { if !$0 { viewModel.declineConsent() } })
      ) {
        if let consent = viewModel.consent {
          IdentityConsentSheet(
            consent: consent, onAccept: { Task { await viewModel.acceptConsent() } },
            onDecline: { viewModel.declineConsent() })
        }
      }
      .sheet(
        isPresented: Binding(
          get: { viewModel.draftChat != nil }, set: { if !$0 { viewModel.discardDraft() } })
      ) {
        if let person = viewModel.draftChat {
          DraftChatScreen(person: person, viewModel: viewModel)
        }
      }
  }

  private var list: some View {
    List {
      if viewModel.mode != .direct,
        !viewModel.selected.isEmpty || !viewModel.selectedAddresses.isEmpty
      {
        Section("Selected users") {
          ScrollView(.horizontal) {
            HStack(spacing: 12) {
              ForEach(viewModel.selectedAddresses) { address in
                VStack(spacing: 4) {
                  AddressAvatar(address: address, size: 44)
                    .overlay(alignment: .topTrailing) {
                      Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(SysColors.textSecondary)
                        .background(Circle().fill(.white))
                    }
                  Text(address.address).textStyle(TextStyles.labelSmall).lineLimit(1)
                    .frame(width: 56)
                }
                .onTapGesture { Task { await viewModel.tap(address) } }
                .transition(.scale.combined(with: .opacity))
              }
              ForEach(viewModel.selected) { person in
                VStack(spacing: 4) {
                  TwakeAvatar(name: person.name, size: 44)
                    .overlay(alignment: .topTrailing) {
                      Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(SysColors.textSecondary)
                        .background(Circle().fill(.white))
                    }
                  Text(person.name).textStyle(TextStyles.labelSmall).lineLimit(1).frame(width: 56)
                }
                .onTapGesture { Task { await viewModel.tap(person) } }
                .transition(.scale.combined(with: .opacity))
              }
            }
            .padding(.vertical, 4)
          }
          .scrollIndicators(.hidden)
        }
      }
      Section {
        ForEach(viewModel.results) { person in
          Button {
            Task { await viewModel.tap(person) }
          } label: {
            HStack(spacing: 12) {
              TwakeAvatar(name: person.name, size: 40)
              VStack(alignment: .leading, spacing: 0) {
                Text(person.name).textStyle(TextStyles.titleMedium).foregroundStyle(
                  SysColors.onSurface
                )
                .lineLimit(1)
                Text(person.id).textStyle(TextStyles.bodySmall).foregroundStyle(
                  SysColors.textSecondary
                )
                .lineLimit(1)
              }
              Spacer()
              if viewModel.mode != .direct {
                Image(systemName: viewModel.isSelected(person) ? "checkmark.circle.fill" : "circle")
                  .foregroundStyle(
                    viewModel.isSelected(person) ? SysColors.primary : SysColors.outline
                  )
                  .contentTransition(.symbolEffect(.replace))
              }
            }
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .accessibilityIdentifier(A11yIdentifiers.newChat.person(person.id))
        }
      } footer: {
        if viewModel.query.isEmpty {
          Text(
            viewModel.offersAddressInvites
              ? "Search for people by name, Matrix ID, e-mail or phone number."
              : "Search for people by name or Matrix ID, such as @alice:example.org.")
        } else if viewModel.results.isEmpty, viewModel.typedAddress == nil,
          !viewModel.isSearching
        {
          Text("No results found")
        }
      }
      if let address = viewModel.typedAddress {
        Section {
          Button {
            Task { await viewModel.tap(address) }
          } label: {
            HStack(spacing: 12) {
              AddressAvatar(address: address, size: 40)
              VStack(alignment: .leading, spacing: 0) {
                Text(address.address).textStyle(TextStyles.titleMedium)
                  .foregroundStyle(SysColors.onSurface).lineLimit(1)
                Text(address.kind == .email ? "Invite by e-mail" : "Invite by text message")
                  .textStyle(TextStyles.bodySmall).foregroundStyle(SysColors.textSecondary)
              }
              Spacer()
              if viewModel.mode != .direct {
                Image(
                  systemName: viewModel.isSelected(address) ? "checkmark.circle.fill" : "circle"
                )
                .foregroundStyle(
                  viewModel.isSelected(address) ? SysColors.primary : SysColors.outline
                )
                .contentTransition(.symbolEffect(.replace))
              }
            }
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
        } footer: {
          Text("No account yet? They get an invitation and join you once they sign up.")
        }
        .transition(.opacity)
      }
      if let twakeContacts, viewModel.mode == .direct {
        AddressBookSection(contacts: twakeContacts, search: viewModel)
        if let message = twakeContacts.errorMessage {
          Section { Text(message).foregroundStyle(SysColors.error) }
        }
      }
      if let phoneContacts, viewModel.mode == .direct {
        PhoneContactsSections(contacts: phoneContacts, search: viewModel, twake: twakeContacts)
      }
      if let message = viewModel.errorMessage {
        Section { Text(message).foregroundStyle(SysColors.error) }
      }
    }
    .searchable(
      text: $viewModel.query, placement: .navigationBarDrawer(displayMode: .always),
      prompt: "Search"
    )
    .textInputAutocapitalization(.never)
    .autocorrectionDisabled()
    .onSubmit(of: .search) { Task { await viewModel.search() } }
    .overlay {
      if viewModel.isSearching || viewModel.isCreating { ProgressView() }
    }
    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: viewModel.selected)
    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: viewModel.selectedAddresses)
    .animation(.easeInOut(duration: 0.2), value: viewModel.results)
    .animation(.easeInOut(duration: 0.2), value: viewModel.typedAddress)
    .sensoryFeedback(.selection, trigger: viewModel.selected)
    .sensoryFeedback(.selection, trigger: viewModel.selectedAddresses)
  }
}

/// The new chat sheet: New direct message or New Group Chat; a group also takes a name.
public struct NewChatScreen: View {
  @Bindable var viewModel: PeopleSearchViewModel
  @Environment(\.dismiss) private var dismiss

  public init(viewModel: PeopleSearchViewModel) {
    self.viewModel = viewModel
  }

  public var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        Picker(
          "Kind", selection: Binding(get: { viewModel.mode }, set: { viewModel.switchMode($0) })
        ) {
          Text("Direct").tag(PeopleSearchViewModel.Mode.direct)
          Text("Group").tag(PeopleSearchViewModel.Mode.group)
          Text("Broadcast").tag(PeopleSearchViewModel.Mode.broadcast)
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        if viewModel.mode == .group {
          TextField("Group name", text: $viewModel.groupName)
            .accessibilityIdentifier(A11yIdentifiers.newChat.groupName)
            .textStyle(TextStyles.bodyLarge)
            .padding(12)
            .background(SysColors.surface, in: .rect(cornerRadius: 12))
            .padding(.horizontal, 16)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
        if viewModel.mode == .broadcast {
          BroadcastForm(viewModel: viewModel)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
        PeopleSearchList(viewModel: viewModel)
      }
      .animation(.spring(response: 0.35, dampingFraction: 0.85), value: viewModel.mode)
      .background(SysColors.background)
      .twakeTitle("New chat")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
        if viewModel.mode == .group {
          ToolbarItem(placement: .confirmationAction) {
            Button("Create") { Task { await viewModel.createGroup() } }
              .disabled(!viewModel.canCreateGroup)
              .accessibilityIdentifier(A11yIdentifiers.newChat.create)
          }
        }
        if viewModel.mode == .broadcast {
          ToolbarItem(placement: .confirmationAction) {
            Button("Create") { Task { await viewModel.createBroadcast() } }
              .disabled(!viewModel.canCreateBroadcast)
          }
        }
      }
    }
  }
}

/// The Contacts tab: search the homeserver's people; a tap opens the direct chat.
public struct ContactsScreen: View {
  let viewModel: PeopleSearchViewModel
  let phoneContacts: PhoneContactsViewModel?
  let twakeContacts: TwakeContactsViewModel?
  @State private var isAddingContact = false

  public init(
    viewModel: PeopleSearchViewModel, phoneContacts: PhoneContactsViewModel? = nil,
    twakeContacts: TwakeContactsViewModel? = nil
  ) {
    self.viewModel = viewModel
    self.phoneContacts = phoneContacts
    self.twakeContacts = twakeContacts
  }

  public var body: some View {
    PeopleSearchList(
      viewModel: viewModel, phoneContacts: phoneContacts, twakeContacts: twakeContacts
    )
    .scrollContentBackground(.hidden)
    .background(SysColors.background)
    .twakeTitle("Contacts")
    .toolbar {
      if let twakeContacts {
        TwakeContactsToolbar(contacts: twakeContacts, isAdding: $isAddingContact)
      }
    }
    .sheet(isPresented: $isAddingContact) {
      if let twakeContacts { AddressBookContactSheet(contacts: twakeContacts) }
    }
    .task {
      async let phone: Void? = phoneContacts?.load()
      async let twake: Void? = twakeContacts?.load()
      _ = await (phone, twake)
    }
  }
}

/// People to invite into a room, as the Flutter "Add members" page: search, pick, then Invite. It closes once they are
/// invited.
public struct InviteScreen: View {
  @Bindable var viewModel: PeopleSearchViewModel
  @Environment(\.dismiss) private var dismiss

  public init(viewModel: PeopleSearchViewModel) {
    self.viewModel = viewModel
  }

  public var body: some View {
    NavigationStack {
      PeopleSearchList(viewModel: viewModel)
        .navigationTitle("Add people")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { dismiss() }
          }
          ToolbarItem(placement: .confirmationAction) {
            Button("Invite") { Task { await viewModel.inviteSelected() } }
              .disabled(
                (viewModel.selected.isEmpty && viewModel.selectedAddresses.isEmpty)
                  || viewModel.isCreating)
          }
        }
        .onChange(of: viewModel.didInvite) { _, invited in if invited { dismiss() } }
    }
  }
}

/// The Broadcast of the new chat sheet (web D90): name, description, who follows (fixed once created), its address
/// when open, and whether followers react. The people picked below are invited to follow.
struct BroadcastForm: View {
  @Bindable var viewModel: PeopleSearchViewModel

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      TextField("Broadcast name", text: $viewModel.broadcast.name)
        .textStyle(TextStyles.bodyLarge)
        .padding(12)
        .background(SysColors.surface, in: .rect(cornerRadius: 12))
      TextField("Description (optional)", text: $viewModel.broadcast.topic, axis: .vertical)
        .lineLimit(1...3)
        .textStyle(TextStyles.bodyMedium)
        .padding(12)
        .background(SysColors.surface, in: .rect(cornerRadius: 12))
      Picker("Who follows", selection: $viewModel.broadcast.access) {
        Label("Anyone", systemImage: "globe").tag(BroadcastDraft.Access.open)
        Label("On approval", systemImage: "hand.raised").tag(BroadcastDraft.Access.approval)
        Label("Invited people", systemImage: "envelope").tag(BroadcastDraft.Access.invitation)
      }
      .pickerStyle(.menu)
      if viewModel.broadcast.access == .open {
        HStack(spacing: 2) {
          Text("#").foregroundStyle(SysColors.textSecondary)
          TextField(
            "address",
            text: Binding(
              get: { viewModel.broadcast.slug },
              set: {
                viewModel.isSlugEdited = true
                viewModel.broadcast.slug = $0.lowercased()
              })
          )
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
        }
        .textStyle(TextStyles.bodyMedium)
        .padding(12)
        .background(SysColors.surface, in: .rect(cornerRadius: 12))
        .overlay(
          RoundedRectangle(cornerRadius: 12).strokeBorder(
            SysColors.error.opacity(
              viewModel.broadcast.slug.isEmpty
                || BroadcastDraft.isValidSlug(viewModel.broadcast.slug)
                ? 0 : 0.8))
        )
        .transition(.move(edge: .top).combined(with: .opacity))
      }
      Toggle("Followers can react", isOn: $viewModel.broadcast.allowsReactions)
      Text(footer)
        .textStyle(TextStyles.labelSmall)
        .foregroundStyle(SysColors.textSecondary)
        .contentTransition(.opacity)
    }
    .padding(.horizontal, 16)
    .animation(.spring(response: 0.35, dampingFraction: 0.85), value: viewModel.broadcast.access)
  }

  private var footer: String {
    let posting = "Only you and moderators post."
    switch viewModel.broadcast.access {
    case .open: return "\(posting) Listed in the server's directory; anyone can read it."
    case .approval: return "\(posting) Listed in the directory; you approve who follows."
    case .invitation: return "\(posting) Only the people you invite follow it."
    }
  }
}

/// A chat with someone new, before it exists (Flutter `chat_draft`): the person, an invitation to write, and a
/// composer. Sending the first message creates the chat; Cancel creates nothing.
public struct DraftChatScreen: View {
  let person: Person
  @Bindable var viewModel: PeopleSearchViewModel
  @FocusState private var isWriting: Bool
  @Environment(\.dismiss) private var dismiss

  public init(person: Person, viewModel: PeopleSearchViewModel) {
    self.person = person
    self.viewModel = viewModel
  }

  public var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        Spacer()
        VStack(spacing: 8) {
          TwakeAvatar(name: person.name, size: 72)
          Text(person.name).textStyle(TextStyles.titleMedium).lineLimit(1)
          Text("No message here yet").textStyle(TextStyles.bodyMedium)
          Text("Send a message to start the conversation")
            .textStyle(TextStyles.bodyMedium)
            .foregroundStyle(SysColors.textSecondary)
            .multilineTextAlignment(.center)
        }
        .padding(24)
        Spacer()
        if let message = viewModel.errorMessage {
          Text(message)
            .textStyle(TextStyles.bodySmall)
            .foregroundStyle(.red)
            .padding(.horizontal, 16)
        }
        HStack(alignment: .bottom, spacing: 8) {
          TextField("Type a message", text: $viewModel.draftText, axis: .vertical)
            .lineLimit(1...5)
            .focused($isWriting)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(SysColors.surface, in: .rect(cornerRadius: 20))
          Button {
            Task { await viewModel.sendDraft() }
          } label: {
            if viewModel.isCreating {
              ProgressView()
            } else {
              Image(systemName: "paperplane.fill")
            }
          }
          .frame(width: 40, height: 40)
          .disabled(!viewModel.canSendDraft)
          .accessibilityLabel("Send")
        }
        .padding(12)
      }
      .background(SysColors.background)
      .navigationTitle(person.name)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") {
            viewModel.discardDraft()
            dismiss()
          }
        }
      }
      .onAppear { isWriting = true }
    }
  }
}
