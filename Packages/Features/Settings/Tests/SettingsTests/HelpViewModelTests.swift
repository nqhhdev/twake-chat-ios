import Domain
import Foundation
import Testing

@testable import Settings

@MainActor
struct HelpViewModelTests {
  private final class Opened {
    var userIds: [String] = []
    var succeeds = true
  }

  private let twake = ServerCapabilities(
    twakeChat: .init(supportContact: "@support:example.org"),
    build: BuildServices(supportURL: URL(string: "https://help.example.org")))

  @Test func helpAndTheSupportChatShowWhenTheyAreAnnounced() async {
    let opened = Opened()
    let model = HelpViewModel(capabilities: FixedCapabilities(value: twake)) {
      opened.userIds.append($0)
      return opened.succeeds
    }
    await model.load()
    #expect(model.helpURL?.absoluteString == "https://help.example.org")
    #expect(model.supportContact == "@support:example.org")
    await model.chatWithSupport()
    #expect(opened.userIds == ["@support:example.org"])
    #expect(model.errorMessage == nil)
    opened.succeeds = false
    await model.chatWithSupport()
    #expect(model.errorMessage == "Could not open the chat with support.")
  }

  @Test func nothingShowsOnAPlainServerWithoutASupportURL() async {
    let model = HelpViewModel(capabilities: FixedCapabilities(value: .none)) { _ in true }
    await model.load()
    #expect(!model.hasRows)
  }

  @Test func noSupportChatWhenTheAppCannotOpenChats() async {
    let model = HelpViewModel(capabilities: FixedCapabilities(value: twake), openDirectChat: nil)
    await model.load()
    #expect(model.supportContact == nil)
    #expect(model.hasRows)
  }
}
