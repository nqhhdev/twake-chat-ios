import Domain
import Foundation
import RoomTestSupport
import Testing

@testable import Room

@MainActor
struct TranscriptionTests {
  struct Transcriber: VoiceTranscribing {
    let result: Result<String, TranscriptionFailure>
    func transcribe(fileURL: URL) async -> Result<String, TranscriptionFailure> { result }
  }

  private func voice(_ id: String? = "$v") -> TimelineMessage {
    TimelineMessage(
      eventId: id, senderId: "@bob:example.org", senderName: "Bob", isOwn: false, date: .now,
      body: .audio(caption: nil), media: MediaReference(source: "s", mimeType: "audio/mp4"))
  }

  private func viewModel(_ result: Result<String, TranscriptionFailure>) -> RoomViewModel {
    let room = RoomViewModel(
      roomId: "!r", roomName: "Team", repository: FakeTimelineRepository(),
      media: FakeMediaRepository())
    room.transcriber = Transcriber(result: result)
    return room
  }

  @Test func onlyASentVoiceMessageCanBeTranscribed() {
    let room = viewModel(.success(""))
    #expect(room.canTranscribe(voice()))
    #expect(!room.canTranscribe(voice(nil)))
    let text = TimelineMessage(
      eventId: "$t", senderId: "@b", senderName: "B", isOwn: false, date: .now, body: .text("hi"))
    #expect(!room.canTranscribe(text))
  }

  @Test func theTextShowsUnderTheVoiceMessageUntilHidden() async {
    let room = viewModel(.success(" See you at noon "))
    let message = voice()
    await room.transcribe(message)
    #expect(room.transcription(of: message) == .transcribed("See you at noon"))
    #expect(!room.canTranscribe(message))
    room.hideTranscription(of: message)
    #expect(room.transcription(of: message) == nil)
  }

  @Test func silenceSaysNoSpeechWasRecognised() async {
    let room = viewModel(.success("  "))
    await room.transcribe(voice())
    #expect(room.transcription(of: voice()) == .transcribed("No speech was recognised."))
  }

  @Test(arguments: [
    (
      TranscriptionFailure.denied,
      "Allow speech recognition for Twake Chat in Settings to transcribe voice messages."
    ),
    (.unavailable, "This device cannot transcribe this language without a connection."),
    (.failed, "Could not transcribe this voice message."),
  ])
  func aFailureSaysWhy(failure: TranscriptionFailure, message: String) async {
    let room = viewModel(.failure(failure))
    await room.transcribe(voice())
    #expect(room.transcription(of: voice()) == nil)
    #expect(room.errorMessage == message)
  }
}
