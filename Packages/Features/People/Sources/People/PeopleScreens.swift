import DesignSystem
import Domain
import SwiftUI

/// The search field and results shared by the new chat sheet and the Contacts tab.
struct PeopleSearchList: View {
  @Bindable var viewModel: PeopleSearchViewModel

  var body: some View {
    List {
      if viewModel.mode != .direct, !viewModel.selected.isEmpty {
        Section("Selected users") {
          ScrollView(.horizontal) {
            HStack(spacing: 12) {
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
        }
      } footer: {
        if viewModel.query.isEmpty {
          Text("Search for people by name or Matrix ID, such as @alice:example.org.")
        } else if viewModel.results.isEmpty, !viewModel.isSearching {
          Text("No results found")
        }
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
    .animation(.easeInOut(duration: 0.2), value: viewModel.results)
    .sensoryFeedback(.selection, trigger: viewModel.selected)
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
          Text("New direct message").tag(PeopleSearchViewModel.Mode.direct)
          Text("New Group Chat").tag(PeopleSearchViewModel.Mode.group)
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        if viewModel.mode == .group {
          TextField("Group name", text: $viewModel.groupName)
            .textStyle(TextStyles.bodyLarge)
            .padding(12)
            .background(SysColors.surface, in: .rect(cornerRadius: 12))
            .padding(.horizontal, 16)
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
          }
        }
      }
    }
  }
}

/// The Contacts tab: search the homeserver's people; a tap opens the direct chat.
public struct ContactsScreen: View {
  let viewModel: PeopleSearchViewModel

  public init(viewModel: PeopleSearchViewModel) {
    self.viewModel = viewModel
  }

  public var body: some View {
    PeopleSearchList(viewModel: viewModel)
      .scrollContentBackground(.hidden)
      .background(SysColors.background)
      .twakeTitle("Contacts")
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
              .disabled(viewModel.selected.isEmpty || viewModel.isCreating)
          }
        }
        .onChange(of: viewModel.didInvite) { _, invited in if invited { dismiss() } }
    }
  }
}
