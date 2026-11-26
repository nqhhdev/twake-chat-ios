import DesignSystem
import Domain
import SwiftUI

struct AddressBookSection: View {
  let contacts: TwakeContactsViewModel
  let search: PeopleSearchViewModel
  @State private var editing: AddressBookEntry?
  @State private var removing: AddressBookEntry?

  var body: some View {
    let shown = contacts.filtered(by: search.query)
    if contacts.features.addressBook, !shown.isEmpty {
      Section("My contacts") {
        ForEach(shown) { entry in
          Button {
            Task { await search.tap(Person(id: entry.userId, displayName: entry.name)) }
          } label: {
            HStack(spacing: 12) {
              TwakeAvatar(name: entry.name, size: 40)
              VStack(alignment: .leading, spacing: 0) {
                Text(entry.name).textStyle(TextStyles.titleMedium)
                  .foregroundStyle(SysColors.onSurface).lineLimit(1)
                Text(entry.userId).textStyle(TextStyles.bodySmall)
                  .foregroundStyle(SysColors.textSecondary).lineLimit(1)
              }
              Spacer()
            }
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .swipeActions {
            Button("Remove", role: .destructive) { removing = entry }
            Button("Edit") { editing = entry }.tint(SysColors.primary)
          }
          .contextMenu {
            Button("Edit", systemImage: "pencil") { editing = entry }
            Button("Remove", systemImage: "trash", role: .destructive) { removing = entry }
          }
        }
      }
      .sheet(item: $editing) { entry in
        AddressBookContactSheet(contacts: contacts, editing: entry)
      }
      .confirmationDialog(
        "Remove \(removing?.name ?? "")?",
        isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
        titleVisibility: .visible
      ) {
        Button("Remove", role: .destructive) {
          if let entry = removing { Task { await contacts.remove(entry) } }
        }
      } message: {
        Text("They leave your contacts on every device. Your chats with them stay.")
      }
    }
  }
}

struct AddressBookContactSheet: View {
  let contacts: TwakeContactsViewModel
  var editing: AddressBookEntry?
  var userId = ""
  @State private var name = ""
  @State private var matrixId = ""
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      Form {
        Section {
          TextField("Name", text: $name)
            .textContentType(.name)
          TextField("@alice:example.org", text: $matrixId)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .keyboardType(.emailAddress)
            .disabled(editing != nil)
            .foregroundStyle(editing == nil ? SysColors.onSurface : SysColors.textSecondary)
        } footer: {
          Text("Your contacts are kept by your Twake server and show on all your devices.")
        }
        if let message = contacts.errorMessage {
          Section { Text(message).foregroundStyle(SysColors.error) }
        }
      }
      .navigationTitle(editing == nil ? "New contact" : "Edit contact")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") {
            contacts.clearError()
            dismiss()
          }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save") {
            Task {
              var saved = false
              if let editing {
                saved = await contacts.rename(editing, to: name)
              } else {
                saved = await contacts.add(userId: matrixId, displayName: name)
              }
              if saved { dismiss() }
            }
          }
          .disabled(contacts.isWorking || name.trimmingCharacters(in: .whitespaces).isEmpty)
        }
      }
      .onAppear {
        contacts.clearError()
        name = editing?.displayName ?? ""
        matrixId = editing?.userId ?? userId
      }
    }
    .presentationDetents([.medium])
  }
}

public struct InvitationsScreen: View {
  let contacts: TwakeContactsViewModel

  public init(contacts: TwakeContactsViewModel) {
    self.contacts = contacts
  }

  public var body: some View {
    Group {
      if let invitations = contacts.invitations {
        if invitations.isEmpty {
          ContentUnavailableView(
            "No invitations", systemImage: "envelope.open",
            description: Text("People you invite by e-mail, text message or link show here."))
        } else {
          List {
            ForEach(invitations) { invitation in
              InvitationRow(invitation: invitation)
                .swipeActions {
                  Button("Check", systemImage: "arrow.clockwise") {
                    Task { await contacts.refresh(invitation) }
                  }
                  .tint(SysColors.primary)
                }
            }
            if let message = contacts.errorMessage {
              Text(message).foregroundStyle(SysColors.error)
            }
          }
          .refreshable { await contacts.loadInvitations() }
        }
      } else {
        ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
    .twakeTitle("Invitations")
    .toolbar {
      ToolbarItem(placement: .primaryAction) { InviteLinkButton(contacts: contacts) }
    }
    .task { await contacts.loadInvitations() }
  }
}

struct InvitationRow: View {
  let invitation: TwakeInvitation

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: icon)
        .foregroundStyle(SysColors.primary)
        .frame(width: 40, height: 40)
        .background(SysColors.primaryContainer, in: Circle())
      VStack(alignment: .leading, spacing: 2) {
        Text(invitation.recipient.isEmpty ? "Invitation link" : invitation.recipient)
          .textStyle(TextStyles.titleMedium).lineLimit(1)
        Text(statusText).textStyle(TextStyles.bodySmall)
          .foregroundStyle(statusColor)
      }
    }
    .accessibilityElement(children: .combine)
  }

  private var icon: String {
    switch invitation.kind {
    case .email: "envelope.fill"
    case .phone: "message.fill"
    case nil: "link"
    }
  }

  private var statusText: String {
    switch invitation.status() {
    case .joined(let userId): "Joined as \(userId)"
    case .opened: "Opened, not joined yet"
    case .pending: "Sent"
    case .expired: "Expired"
    }
  }

  private var statusColor: ColorToken {
    switch invitation.status() {
    case .joined: SysColors.primary
    case .expired: SysColors.error
    case .opened, .pending: SysColors.textSecondary
    }
  }
}

struct InviteLinkButton: View {
  let contacts: TwakeContactsViewModel

  var body: some View {
    if let link = contacts.link {
      ShareLink(
        item: link.url, subject: Text("Join me on Twake Chat"),
        message: Text("Join me on Twake Chat: \(link.url.absoluteString)")
      ) {
        Label("Share invitation link", systemImage: "square.and.arrow.up")
      }
    } else {
      Button("Create invitation link", systemImage: "link") {
        Task { await contacts.makeLink() }
      }
      .disabled(contacts.isWorking)
    }
  }
}

struct TwakeContactsToolbar: ToolbarContent {
  let contacts: TwakeContactsViewModel
  @Binding var isAdding: Bool

  var body: some ToolbarContent {
    if contacts.features.addressBook || contacts.features.invitations {
      ToolbarItem(placement: .primaryAction) {
        Menu {
          if contacts.features.addressBook {
            Button("New contact", systemImage: "person.badge.plus") { isAdding = true }
          }
          if contacts.features.invitations {
            InviteLinkButton(contacts: contacts)
            NavigationLink {
              InvitationsScreen(contacts: contacts)
            } label: {
              Label("Invitations", systemImage: "envelope.open")
            }
          }
        } label: {
          Image(systemName: "plus")
        }
        .accessibilityLabel("Add")
      }
    }
  }
}
