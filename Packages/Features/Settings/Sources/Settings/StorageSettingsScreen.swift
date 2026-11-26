import DesignSystem
import Domain
import SwiftUI

struct StorageSettingsScreen: View {
  let viewModel: SettingsViewModel
  @State private var isConfirming = false
  @State private var isAddingEmail = false
  @State private var newEmail = ""
  @State private var isAddingPhone = false
  @State private var newPhone = ""
  @State private var removing: LinkedAddress?

  var body: some View {
    List {
      if let addresses = viewModel.linkedAddresses,
        !addresses.isEmpty || viewModel.canChangeLinkedAddresses
      {
        Section {
          ForEach(addresses) { address in
            Label(address.address, systemImage: address.kind == .email ? "envelope" : "phone")
              .textSelection(.enabled)
              .swipeActions {
                if viewModel.canChangeLinkedAddresses {
                  Button(localized("Remove"), role: .destructive) { removing = address }
                }
              }
          }
          if viewModel.canChangeLinkedAddresses {
            Button(localized("Add e-mail"), systemImage: "plus") { isAddingEmail = true }
              .disabled(viewModel.isChangingAddresses)
            Button(localized("Add phone number"), systemImage: "plus") { isAddingPhone = true }
              .disabled(viewModel.isChangingAddresses)
          }
        } header: {
          Text(localized("E-mails and phones"))
        } footer: {
          Text(localized("People who have these in their contacts can find you."))
        }
      }
      if let visibility = viewModel.contactsVisibility {
        Section {
          Picker(
            localized("Who sees them"),
            selection: Binding(
              get: { visibility },
              set: { new in Task { await viewModel.setContactsVisibility(new) } })
          ) {
            Text(localized("Nobody")).tag(ContactsVisibility.nobody)
            Text(localized("My contacts")).tag(ContactsVisibility.contacts)
            Text(localized("Everyone")).tag(ContactsVisibility.everyone)
          }
          .pickerStyle(.inline)
          .labelsHidden()
        } header: {
          Text(localized("Who sees my e-mail and phone"))
        }
        .transition(.opacity)
      }
      Section {
        LabeledContent(localized("Cache")) {
          if let size = viewModel.cacheSize {
            Text(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
              .contentTransition(.numericText(value: Double(size)))
          } else {
            ProgressView()
          }
        }
        Button(localized("Clear Cache"), role: .destructive) { isConfirming = true }
          .disabled(viewModel.isClearingCache)
      } footer: {
        Text(
          localized(
            "Messages and media load again from the server. Your keys and session stay on this device."
          )
        )
      }
      if let message = viewModel.errorMessage {
        Section { Text(message).foregroundStyle(SysColors.error) }
      }
    }
    .twakeTitle(localized("Data and Storage"))
    .overlay { if viewModel.isClearingCache { ProgressView().controlSize(.large) } }
    .animation(.spring(response: 0.4, dampingFraction: 0.85), value: viewModel.cacheSize)
    .animation(.easeInOut(duration: 0.25), value: viewModel.contactsVisibility)
    .sensoryFeedback(.selection, trigger: viewModel.contactsVisibility)
    .task {
      async let size: Void = viewModel.loadCacheSize()
      async let addresses: Void = viewModel.loadLinkedAddresses()
      async let visibility: Void = viewModel.loadContactsVisibility()
      _ = await (size, addresses, visibility)
    }
    .confirmationDialog(
      localized("Clear the cache?"), isPresented: $isConfirming, titleVisibility: .visible
    ) {
      Button(localized("Clear Cache"), role: .destructive) { Task { await viewModel.clearCache() } }
    }
    .overlay { if viewModel.isChangingAddresses { ProgressView().controlSize(.large) } }
    .modifier(LinkedAddressDialogs(viewModel: viewModel))
    .alert(localized("Add an e-mail"), isPresented: $isAddingEmail) {
      TextField(localized("E-mail"), text: $newEmail)
        .keyboardType(.emailAddress)
        .textContentType(.emailAddress)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
      Button(localized("Cancel"), role: .cancel) { newEmail = "" }
      Button(localized("Send link")) {
        let typed = newEmail
        newEmail = ""
        Task { await viewModel.addEmail(typed) }
      }
    } message: {
      Text(localized("We will send a link to this address to confirm it is yours."))
    }
    .alert(localized("Add a phone number"), isPresented: $isAddingPhone) {
      TextField("+33 6 12 34 56 78" as String, text: $newPhone)
        .keyboardType(.phonePad)
        .textContentType(.telephoneNumber)
      Button(localized("Cancel"), role: .cancel) { newPhone = "" }
      Button(localized("Send code")) {
        let typed = newPhone
        newPhone = ""
        Task { await viewModel.addPhone(typed) }
      }
    } message: {
      Text(localized("We will send a code to this number by text message to confirm it is yours."))
    }
    .confirmationDialog(
      localized("Remove \(removing?.address ?? "")?"),
      isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
      titleVisibility: .visible
    ) {
      Button(localized("Remove"), role: .destructive) {
        if let address = removing { Task { await viewModel.removeLinkedAddress(address) } }
      }
    } message: {
      Text(localized("People will no longer find you by it."))
    }
  }
}

private struct LinkedAddressDialogs: ViewModifier {
  let viewModel: SettingsViewModel
  @State private var password = ""
  @State private var code = ""

  func body(content: Content) -> some View {
    content
      .alert(
        localized("Enter the code"),
        isPresented: Binding(
          get: {
            viewModel.pendingPhone != nil && viewModel.linkChallenge == nil
              && !viewModel.isChangingAddresses
          },
          set: { if !$0 { code = "" } })
      ) {
        TextField(localized("Code"), text: $code)
          .keyboardType(.numberPad)
          .textContentType(.oneTimeCode)
        Button(localized("Cancel"), role: .cancel) { viewModel.cancelLinking() }
        Button(localized("Confirm")) {
          let typed = code
          code = ""
          Task { await viewModel.submitPhoneCode(typed) }
        }
      } message: {
        let phone = viewModel.pendingPhone?.phone ?? ""
        Text(
          viewModel.phoneCodeRejected
            ? localized(
              "This code is not right. Check the text message sent to \(phone) and try again.")
            : localized("We sent a code to \(phone). Enter it to confirm the number is yours."))
      }
      .alert(
        localized("Check your inbox"),
        isPresented: Binding(
          get: {
            viewModel.pendingEmail != nil && viewModel.linkChallenge == nil
              && !viewModel.isChangingAddresses
          },
          set: { _ in })
      ) {
        Button(localized("Cancel"), role: .cancel) { viewModel.cancelLinking() }
        Button(localized("I opened the link")) { Task { await viewModel.finishLinkingEmail() } }
      } message: {
        let email = viewModel.pendingEmail?.email ?? ""
        Text(
          viewModel.emailNotConfirmed
            ? localized(
              "The link was not opened yet. Open the link sent to \(email), then try again.")
            : localized("We sent a link to \(email). Open it, then come back here."))
      }
      .sheet(
        isPresented: Binding(
          get: { viewModel.linkChallenge?.webURL != nil },
          set: { if !$0 { Task { await viewModel.confirmLinking() } } })
      ) {
        if let url = viewModel.linkChallenge?.webURL {
          SafariView(url: url).ignoresSafeArea()
        }
      }
      .alert(
        localized("Confirm it is you"),
        isPresented: Binding(
          get: {
            viewModel.linkChallenge.map { $0.webURL == nil && $0.acceptsPassword } ?? false
          },
          set: { if !$0 { password = "" } })
      ) {
        SecureField(localized("Password"), text: $password)
        Button(localized("Cancel"), role: .cancel) { viewModel.cancelLinking() }
        Button(localized("Add")) {
          let typed = password
          password = ""
          Task { await viewModel.confirmLinking(password: typed) }
        }
      } message: {
        Text(
          viewModel.pendingPhone == nil
            ? localized("Enter your account password to add the e-mail.")
            : localized("Enter your account password to add the phone number."))
      }
  }
}
