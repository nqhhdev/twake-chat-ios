import Domain
import Foundation

extension RoomViewModel {
  func loadScheduling() async {
    canSchedule = await repository.canSchedule()
    scheduled = canSchedule ? await repository.scheduledMessages() : []
  }

  var canScheduleDraft: Bool {
    guard canSchedule, canSend else { return false }
    if case .edit = composerMode { return false }
    return true
  }

  func schedule(at date: Date) async -> Bool {
    let typed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
    guard canScheduleDraft, !typed.isEmpty else { return false }
    var replyTo: String?
    if case .reply(let eventId, _) = composerMode { replyTo = eventId }
    errorMessage = nil
    do {
      try await repository.schedule(
        text: Self.applyingMentions(mentions, to: typed), at: date, replyTo: replyTo)
    } catch {
      errorMessage = Self.scheduleMessage(error)
      return false
    }
    draft = ""
    mentions = []
    composerMode = .new
    await repository.setTyping(false)
    scheduled = await repository.scheduledMessages()
    return true
  }

  func cancelScheduled(_ message: ScheduledMessage) async {
    guard await repository.cancelScheduled(id: message.id) else {
      errorMessage = "Could not cancel the scheduled message. It may have been sent already."
      scheduled = await repository.scheduledMessages()
      return
    }
    scheduled.removeAll { $0.id == message.id }
  }

  func sendScheduledNow(_ message: ScheduledMessage) async {
    guard await repository.sendScheduledNow(id: message.id) else {
      errorMessage = "Could not send the scheduled message. It may have been sent already."
      scheduled = await repository.scheduledMessages()
      return
    }
    scheduled.removeAll { $0.id == message.id }
  }

  func editScheduled(_ message: ScheduledMessage) async {
    guard await repository.cancelScheduled(id: message.id) else {
      errorMessage = "Could not change the scheduled message. It may have been sent already."
      scheduled = await repository.scheduledMessages()
      return
    }
    scheduled.removeAll { $0.id == message.id }
    draft = message.text
  }

  static func scheduleMessage(_ error: ScheduleError) -> String {
    switch error {
    case .unsupported: "This server cannot schedule messages."
    case .encryptedRoom: "Messages cannot be scheduled in an encrypted chat."
    case .delayTooLong(let maxDelay):
      maxDelay.map {
        "The server cannot hold a message that long (at most \(Int(($0 / 3600).rounded(.down))) hours)."
      } ?? "The server cannot hold a message that long."
    case .tooMany: "Too many messages are scheduled. Cancel one first."
    case .failed: "Could not schedule your message. Please try again."
    }
  }
}
