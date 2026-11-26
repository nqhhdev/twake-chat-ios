import Domain
import Foundation
import RoomTestSupport
import Testing

@testable import Room

@MainActor
struct TranslationTests {
  private func message(own: Bool = false, body: TimelineMessage.Body = .text("Bonjour"))
    -> TimelineMessage
  {
    TimelineMessage(
      eventId: "$1", senderId: own ? "@me:example.org" : "@bob:example.org",
      senderName: own ? "Me" : "Bob", isOwn: own, date: .now, body: body)
  }

  private func viewModel() -> RoomViewModel {
    RoomViewModel(
      roomId: "!r", roomName: "Team", repository: FakeTimelineRepository(),
      media: FakeMediaRepository())
  }

  @Test func onlySomeoneElsesTextCanBeTranslated() {
    let room = viewModel()
    #expect(room.canTranslate(message()))
    #expect(!room.canTranslate(message(own: true)))
    #expect(!room.canTranslate(message(body: .image(caption: "x"))))
    #expect(!room.canTranslate(message(body: .text("   "))))
  }

  @Test func theTranslationReplacesTheTextUntilTheOriginalIsShown() {
    let room = viewModel()
    let bonjour = message()
    room.translate(bonjour)
    #expect(room.translation(of: bonjour) == .translating)
    #expect(!room.canTranslate(bonjour))
    room.finishTranslation(of: "$1", text: " Hello ")
    #expect(room.translation(of: bonjour) == .translated("Hello"))
    room.showOriginal(bonjour)
    #expect(room.translation(of: bonjour) == nil)
    #expect(room.canTranslate(bonjour))
  }

  @Test func aFailedTranslationSaysSoAndKeepsTheOriginal() {
    let room = viewModel()
    let bonjour = message()
    room.translate(bonjour)
    room.finishTranslation(of: "$1", text: nil)
    #expect(room.translation(of: bonjour) == nil)
    #expect(room.errorMessage == "Could not translate this message.")
  }

  @Test func aLateAnswerAfterShowingTheOriginalIsIgnored() {
    let room = viewModel()
    let bonjour = message()
    room.translate(bonjour)
    room.showOriginal(bonjour)
    room.finishTranslation(of: "$1", text: "Hello")
    #expect(room.translation(of: bonjour) == nil)
  }

  @Test func theFormattedTextIsWhatIsTranslated() {
    var formatted = AttributedString("Bonjour ")
    formatted += AttributedString("Bob")
    let rich = TimelineMessage(
      eventId: "$1", senderId: "@bob:example.org", senderName: "Bob", isOwn: false, date: .now,
      body: .text("Bonjour [Bob](https://matrix.to/#/@bob:example.org)"), formatted: formatted)
    #expect(RoomViewModel.translationSource(of: rich) == "Bonjour Bob")
  }
}
