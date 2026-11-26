import DesignSystem
import Domain
import SwiftUI

@MainActor
@Observable
public final class HelpViewModel {
  public private(set) var helpURL: URL?
  public private(set) var supportContact: String?
  public private(set) var errorMessage: String?

  @ObservationIgnored private let capabilities: any ServerCapabilitiesRepository
  @ObservationIgnored private let openDirectChat: (@MainActor (String) async -> Bool)?

  public init(
    capabilities: any ServerCapabilitiesRepository,
    openDirectChat: (@MainActor (String) async -> Bool)?
  ) {
    self.capabilities = capabilities
    self.openDirectChat = openDirectChat
  }

  public var hasRows: Bool { helpURL != nil || supportContact != nil }

  public func load() async {
    let current = await capabilities.current()
    helpURL = current.build.supportURL
    supportContact = openDirectChat == nil ? nil : current.supportContact
  }

  public func chatWithSupport() async {
    errorMessage = nil
    guard let supportContact, let openDirectChat else { return }
    if await !openDirectChat(supportContact) {
      errorMessage = localized("Could not open the chat with support.")
    }
  }
}

struct HelpSection: View {
  let viewModel: HelpViewModel

  var body: some View {
    if viewModel.hasRows {
      Section {
        if let url = viewModel.helpURL {
          Link(destination: url) {
            SettingsRow(title: localized("Help"), icon: "questionmark.circle", detail: nil)
          }
          .accessibilityIdentifier("settings.help")
        }
        if viewModel.supportContact != nil {
          Button {
            Task { await viewModel.chatWithSupport() }
          } label: {
            SettingsRow(
              title: localized("Chat with Support"), icon: "bubble.left.and.text.bubble.right",
              detail: nil)
          }
          .accessibilityIdentifier("settings.supportChat")
        }
        if let message = viewModel.errorMessage {
          Text(message).foregroundStyle(SysColors.error)
        }
      }
    }
  }
}
