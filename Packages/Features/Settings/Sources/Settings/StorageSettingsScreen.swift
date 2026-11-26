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
                  Button("Remove", role: .destructive) { removing = address }
                }
              }
          }
          if viewModel.canChangeLinkedAddresses {
            Button("Add e-mail", systemImage: "plus") { isAddingEmail = true }
              .disabled(viewModel.isChangingAddresses)
            Button("Add phone number", systemImage: "plus") { isAddingPhone = true }
              .disabled(viewModel.isChangingAddresses)
          }
        } header: {
          Text("E-mails and phones")
        } footer: {
          Text("People who have these in their contacts can find you.")
        }
      }
      if let visibility = viewModel.contactsVisibility {
        Section {
          Picker(
            "Who sees them",
            selection: Binding(
              get: { visibility },
              set: { new in Task { await viewModel.setContactsVisibility(new) } })
          ) {
            Text("Nobody").tag(ContactsVisibility.nobody)
            Text("My contacts").tag(ContactsVisibility.contacts)
            Text("Everyone").tag(ContactsVisibility.everyone)
          }
          .pickerStyle(.inline)
          .labelsHidden()
        } header: {
          Text("Who sees my e-mail and phone")
        }
        .transition(.opacity)
      }
      Section {
        LabeledContent("Cache") {
          if let size = viewModel.cacheSize {
            Text(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
              .contentTransition(.numericText(value: Double(size)))
          } else {
            ProgressView()
          }
        }
        Button("Clear Cache", role: .destructive) { isConfirming = true }
          .disabled(viewModel.isClearingCache)
      } footer: {
        Text(
          "Messages and media load again from the server. Your keys and session stay on this device."
        )
      }
      if let message = viewModel.errorMessage {
        Section { Text(message).foregroundStyle(SysColors.error) }
      }
    }
    .twakeTitle("Data and Storage")
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
    .confirmationDialog("Clear the cache?", isPresented: $isConfirming, titleVisibility: .visible) {
      Button("Clear Cache", role: .destructive) { Task { await viewModel.clearCache() } }
    }
    .overlay { if viewModel.isChangingAddresses { ProgressView().controlSize(.large) } }
    .modifier(LinkedAddressDialogs(viewModel: viewModel))
    .alert("Add an e-mail", isPresented: $isAddingEmail) {
      TextField("E-mail", text: $newEmail)
        .keyboardType(.emailAddress)
        .textContentType(.emailAddress)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
      Button("Cancel", role: .cancel) { newEmail = "" }
      Button("Send link") {
        let typed = newEmail
        newEmail = ""
        Task { await viewModel.addEmail(typed) }
      }
    } message: {
      Text("We will send a link to this address to confirm it is yours.")
    }
    .alert("Add a phone number", isPresented: $isAddingPhone) {
      TextField("+33 6 12 34 56 78", text: $newPhone)
        .keyboardType(.phonePad)
        .textContentType(.telephoneNumber)
      Button("Cancel", role: .cancel) { newPhone = "" }
      Button("Send code") {
        let typed = newPhone
        newPhone = ""
        Task { await viewModel.addPhone(typed) }
      }
    } message: {
      Text("We will send a code to this number by text message to confirm it is yours.")
    }
    .confirmationDialog(
      "Remove \(removing?.address ?? "")?",
      isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
      titleVisibility: .visible
    ) {
      Button("Remove", role: .destructive) {
        if let address = removing { Task { await viewModel.removeLinkedAddress(address) } }
      }
    } message: {
      Text("People will no longer find you by it.")
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
        "Enter the code",
        isPresented: Binding(
          get: {
            viewModel.pendingPhone != nil && viewModel.linkChallenge == nil
              && !viewModel.isChangingAddresses
          },
          set: { if !$0 { code = "" } })
      ) {
        TextField("Code", text: $code)
          .keyboardType(.numberPad)
          .textContentType(.oneTimeCode)
        Button("Cancel", role: .cancel) { viewModel.cancelLinking() }
        Button("Confirm") {
          let typed = code
          code = ""
          Task { await viewModel.submitPhoneCode(typed) }
        }
      } message: {
        let phone = viewModel.pendingPhone?.phone ?? ""
        Text(
          viewModel.phoneCodeRejected
            ? "This code is not right. Check the text message sent to \(phone) and try again."
            : "We sent a code to \(phone). Enter it to confirm the number is yours.")
      }
      .alert(
        "Check your inbox",
        isPresented: Binding(
          get: {
            viewModel.pendingEmail != nil && viewModel.linkChallenge == nil
              && !viewModel.isChangingAddresses
          },
          set: { _ in })
      ) {
        Button("Cancel", role: .cancel) { viewModel.cancelLinking() }
        Button("I opened the link") { Task { await viewModel.finishLinkingEmail() } }
      } message: {
        let email = viewModel.pendingEmail?.email ?? ""
        Text(
          viewModel.emailNotConfirmed
            ? "The link was not opened yet. Open the link sent to \(email), then try again."
            : "We sent a link to \(email). Open it, then come back here.")
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
        "Confirm it is you",
        isPresented: Binding(
          get: {
            viewModel.linkChallenge.map { $0.webURL == nil && $0.acceptsPassword } ?? false
          },
          set: { if !$0 { password = "" } })
      ) {
        SecureField("Password", text: $password)
        Button("Cancel", role: .cancel) { viewModel.cancelLinking() }
        Button("Add") {
          let typed = password
          password = ""
          Task { await viewModel.confirmLinking(password: typed) }
        }
      } message: {
        Text(
          viewModel.pendingPhone == nil
            ? "Enter your account password to add the e-mail."
            : "Enter your account password to add the phone number.")
      }
  }
}
