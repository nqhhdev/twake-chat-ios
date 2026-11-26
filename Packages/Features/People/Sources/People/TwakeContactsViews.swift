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
      Section(localized("My contacts")) {
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
            Button(localized("Remove"), role: .destructive) { removing = entry }
            Button(localized("Edit")) { editing = entry }.tint(SysColors.primary)
          }
          .contextMenu {
            Button(localized("Edit"), systemImage: "pencil") { editing = entry }
            Button(localized("Remove"), systemImage: "trash", role: .destructive) {
              removing = entry
            }
          }
        }
      }
      .sheet(item: $editing) { entry in
        AddressBookContactSheet(contacts: contacts, editing: entry)
      }
      .confirmationDialog(
        localized("Remove \(removing?.name ?? "")?"),
        isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
        titleVisibility: .visible
      ) {
        Button(localized("Remove"), role: .destructive) {
          if let entry = removing { Task { await contacts.remove(entry) } }
        }
      } message: {
        Text(localized("They leave your contacts on every device. Your chats with them stay."))
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
          TextField(localized("Name"), text: $name)
            .textContentType(.name)
          TextField(localized("@alice:example.org"), text: $matrixId)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .keyboardType(.emailAddress)
            .disabled(editing != nil)
            .foregroundStyle(editing == nil ? SysColors.onSurface : SysColors.textSecondary)
        } footer: {
          Text(
            localized("Your contacts are kept by your Twake server and show on all your devices."))
        }
        if let message = contacts.errorMessage {
          Section { Text(message).foregroundStyle(SysColors.error) }
        }
      }
      .navigationTitle(editing == nil ? localized("New contact") : localized("Edit contact"))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(localized("Cancel")) {
            contacts.clearError()
            dismiss()
          }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button(localized("Save")) {
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
            localized("No invitations"), systemImage: "envelope.open",
            description: Text(
              localized("People you invite by e-mail, text message or link show here.")))
        } else {
          List {
            ForEach(invitations) { invitation in
              InvitationRow(invitation: invitation)
                .swipeActions {
                  Button(localized("Check"), systemImage: "arrow.clockwise") {
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
    .twakeTitle(localized("Invitations"))
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
        Text(invitation.recipient.isEmpty ? localized("Invitation link") : invitation.recipient)
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
    case .joined(let userId): localized("Joined as \(userId)")
    case .opened: localized("Opened, not joined yet")
    case .pending: localized("Sent")
    case .expired: localized("Expired")
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
        item: link.url, subject: Text(localized("Join me on Twake Chat")),
        message: Text(localized("Join me on Twake Chat: \(link.url.absoluteString)"))
      ) {
        Label(localized("Share invitation link"), systemImage: "square.and.arrow.up")
      }
    } else {
      Button(localized("Create invitation link"), systemImage: "link") {
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
            Button(localized("New contact"), systemImage: "person.badge.plus") { isAdding = true }
          }
          if contacts.features.invitations {
            InviteLinkButton(contacts: contacts)
            NavigationLink {
              InvitationsScreen(contacts: contacts)
            } label: {
              Label(localized("Invitations"), systemImage: "envelope.open")
            }
          }
        } label: {
          Image(systemName: "plus")
        }
        .accessibilityLabel(localized("Add"))
      }
    }
  }
}
