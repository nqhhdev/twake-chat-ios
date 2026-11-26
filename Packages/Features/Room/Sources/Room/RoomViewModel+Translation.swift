import Domain
import Foundation

public enum MessageTranslation: Equatable, Sendable {
  case translating
  case translated(String)
  case failed
}

extension RoomViewModel {
  static func translationSource(of message: TimelineMessage) -> String? {
    let text: String
    switch message.body {
    case .text(let plain), .notice(let plain), .emote(let plain):
      text = message.formatted.map { String($0.characters) } ?? plain
    default: return nil
    }
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }

  func canTranslate(_ message: TimelineMessage) -> Bool {
    guard !message.isOwn, let id = message.eventId else { return false }
    return translations[id] == nil && Self.translationSource(of: message) != nil
  }

  func translation(of message: TimelineMessage) -> MessageTranslation? {
    message.eventId.flatMap { translations[$0] }
  }

  func translate(_ message: TimelineMessage) {
    guard canTranslate(message), let id = message.eventId else { return }
    translations[id] = .translating
  }

  func finishTranslation(of eventId: String, text: String?) {
    guard translations[eventId] == .translating else { return }
    let translated = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if translated.isEmpty {
      translations[eventId] = nil
      errorMessage = localized("Could not translate this message.")
    } else {
      translations[eventId] = .translated(translated)
    }
  }

  func showOriginal(_ message: TimelineMessage) {
    guard let id = message.eventId else { return }
    translations[id] = nil
  }
}
