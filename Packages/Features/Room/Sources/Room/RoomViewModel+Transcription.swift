import Domain
import Foundation

public enum MessageTranscription: Equatable, Sendable {
  case transcribing
  case transcribed(String)
}

public enum TranscriptionFailure: Error, Equatable, Sendable {
  case denied
  case unavailable
  case failed
}

public protocol VoiceTranscribing: Sendable {
  func transcribe(fileURL: URL) async -> Result<String, TranscriptionFailure>
}

extension RoomViewModel {
  func canTranscribe(_ message: TimelineMessage) -> Bool {
    guard case .audio = message.body, message.media != nil, let id = message.eventId else {
      return false
    }
    return transcriptions[id] == nil
  }

  func transcription(of message: TimelineMessage) -> MessageTranscription? {
    message.eventId.flatMap { transcriptions[$0] }
  }

  func transcribe(_ message: TimelineMessage) async {
    guard canTranscribe(message), let id = message.eventId else { return }
    transcriptions[id] = .transcribing
    guard let url = await file(of: message) else {
      transcriptions[id] = nil
      errorMessage = Self.transcriptionMessage(.failed)
      return
    }
    switch await transcriber.transcribe(fileURL: url) {
    case .success(let text):
      let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
      transcriptions[id] = .transcribed(
        trimmed.isEmpty ? localized("No speech was recognised.") : trimmed)
    case .failure(let failure):
      transcriptions[id] = nil
      errorMessage = Self.transcriptionMessage(failure)
    }
  }

  func hideTranscription(of message: TimelineMessage) {
    guard let id = message.eventId else { return }
    transcriptions[id] = nil
  }

  static func transcriptionMessage(_ failure: TranscriptionFailure) -> String {
    switch failure {
    case .denied:
      localized("Allow speech recognition for Twake Chat in Settings to transcribe voice messages.")
    case .unavailable:
      localized("This device cannot transcribe this language without a connection.")
    case .failed: localized("Could not transcribe this voice message.")
    }
  }
}
