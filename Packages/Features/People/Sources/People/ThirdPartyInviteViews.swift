import DesignSystem
import Domain
import SwiftUI
import UIKit

struct AddressAvatar: View {
  let address: ContactAddress
  let size: CGFloat

  var body: some View {
    Image(systemName: address.kind == .email ? "envelope.fill" : "phone.fill")
      .font(.system(size: size * 0.4))
      .foregroundStyle(SysColors.primary)
      .frame(width: size, height: size)
      .background(SysColors.primaryContainer, in: Circle())
      .accessibilityHidden(true)
  }
}

struct IdentityConsentSheet: View {
  let consent: IdentityConsent
  let onAccept: () -> Void
  let onDecline: () -> Void
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      List {
        Section {
          VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "person.crop.circle.badge.questionmark")
              .font(.system(size: 40))
              .foregroundStyle(SysColors.primary)
            Text("Find people by e-mail or phone")
              .textStyle(TextStyles.titleMedium)
            Text(
              "To find people by their e-mail or phone number and invite them, the app asks the identity server \(consent.server). It only sends a scrambled form (a hash) of the addresses, never the addresses themselves, and nothing is sent before you accept its terms."
            )
            .textStyle(TextStyles.bodyMedium)
            .foregroundStyle(SysColors.textSecondary)
          }
          .padding(.vertical, 8)
        }
        if !consent.policies.isEmpty {
          Section("Terms of \(consent.server)") {
            ForEach(consent.policies) { policy in
              Link(destination: policy.url) {
                Label(policy.title, systemImage: "doc.text")
              }
            }
          }
        }
      }
      .navigationTitle("Identity server")
      .navigationBarTitleDisplayMode(.inline)
      .safeAreaInset(edge: .bottom) {
        VStack(spacing: 8) {
          Button {
            onAccept()
            dismiss()
          } label: {
            Text("Accept and continue").frame(maxWidth: .infinity)
          }
          .buttonStyle(.borderedProminent)
          .controlSize(.large)
          Button("Not now") {
            onDecline()
            dismiss()
          }
        }
        .padding(16)
        .background(.bar)
      }
    }
    .presentationDetents([.medium, .large])
  }
}

struct PhoneContactsSections: View {
  let contacts: PhoneContactsViewModel
  let search: PeopleSearchViewModel
  var twake: TwakeContactsViewModel?
  @State private var isAskingConsent = false
  @Environment(\.openURL) private var openURL

  var body: some View {
    Group {
      switch contacts.state {
      case .hidden:
        EmptyView()
      case .askPermission:
        findButton { Task { await contacts.allowAccess() } }
      case .needsConsent:
        findButton { isAskingConsent = true }
      case .denied:
        Section {
          Button("Allow access to Contacts", systemImage: "gear") {
            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
          }
        } footer: {
          Text("Turn on Contacts for this app in Settings to find the people you know.")
        }
      case .loading:
        Section("From your contacts") {
          HStack {
            Spacer()
            ProgressView()
            Spacer()
          }
        }
      case .failed:
        Section {
          Button("Try again", systemImage: "arrow.clockwise") {
            Task { await contacts.load() }
          }
        } footer: {
          Text("Could not look up your contacts.")
        }
      case .loaded:
        loaded
      }
    }
    .sheet(isPresented: $isAskingConsent) {
      if case .needsConsent(let consent) = contacts.state {
        IdentityConsentSheet(
          consent: consent, onAccept: { Task { await contacts.acceptConsent() } }, onDecline: {})
      }
    }
  }

  @ViewBuilder private var loaded: some View {
    let matched = contacts.filtered(contacts.onMatrix, by: search.query)
    let others = contacts.filtered(contacts.invitable, by: search.query)
    if !matched.isEmpty {
      Section("From your contacts") {
        ForEach(matched) { entry in
          Button {
            guard let userId = entry.userId else { return }
            Task { await search.tap(Person(id: userId, displayName: entry.contact.name)) }
          } label: {
            HStack(spacing: 12) {
              TwakeAvatar(name: entry.contact.name, size: 40)
              VStack(alignment: .leading, spacing: 0) {
                Text(entry.contact.name).textStyle(TextStyles.titleMedium)
                  .foregroundStyle(SysColors.onSurface).lineLimit(1)
                Text(entry.userId ?? "").textStyle(TextStyles.bodySmall)
                  .foregroundStyle(SysColors.textSecondary).lineLimit(1)
              }
              Spacer()
            }
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
        }
      }
    }
    if !others.isEmpty {
      Section {
        ForEach(others) { entry in
          HStack(spacing: 12) {
            TwakeAvatar(name: entry.contact.name, size: 40)
            VStack(alignment: .leading, spacing: 0) {
              Text(entry.contact.name).textStyle(TextStyles.titleMedium).lineLimit(1)
              Text(entry.address.address).textStyle(TextStyles.bodySmall)
                .foregroundStyle(SysColors.textSecondary).lineLimit(1)
            }
            Spacer()
            inviteButton(entry.address)
          }
        }
      } header: {
        Text("Invite to chat")
      } footer: {
        Text("They get an invitation and join you once they sign up.")
      }
    }
  }

  @ViewBuilder private func inviteButton(_ address: ContactAddress) -> some View {
    if let twake, twake.features.invitations {
      if twake.invited[address] != nil {
        Label("Invited", systemImage: "checkmark")
          .labelStyle(.titleAndIcon)
          .textStyle(TextStyles.labelSmall)
          .foregroundStyle(SysColors.textSecondary)
      } else {
        Button("Invite") { Task { _ = await twake.invite(address) } }
          .buttonStyle(.bordered)
          .disabled(twake.isWorking)
      }
    } else {
      Button("Invite") { Task { await search.tap(address) } }
        .buttonStyle(.bordered)
        .disabled(search.isCreating)
    }
  }

  private func findButton(_ action: @escaping () -> Void) -> some View {
    Section {
      Button(
        "Find people from your contacts", systemImage: "person.crop.rectangle.stack", action: action
      )
    } footer: {
      Text(
        "Your contacts' e-mails and phone numbers are checked, in hashed form, against the identity server to show who already uses Matrix. Nothing leaves your device until you allow it."
      )
    }
  }
}
