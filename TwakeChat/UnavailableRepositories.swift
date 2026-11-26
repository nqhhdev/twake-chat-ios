import Domain
import Foundation

struct UnavailableTimeline: TimelineRepository {
  func open() async throws(TimelineError) -> AsyncStream<[TimelineItem]> { throw .unavailable }
  func loadOlder() async throws(TimelineError) -> Bool { throw .unavailable }
  func send(text: String) async throws(TimelineError) { throw .unavailable }
  func send(emote text: String) async throws(TimelineError) { throw .unavailable }
  func sendAttachment(_ attachment: OutgoingAttachment) async throws(TimelineError) {
    throw .unavailable
  }
  func setTyping(_ isTyping: Bool) async {}
  func createPoll(_ draft: PollDraft) async throws(TimelineError) { throw .unavailable }
  func vote(_ answerIds: [String], in pollEventId: String) async throws(TimelineError) {
    throw .unavailable
  }
  func endPoll(_ pollEventId: String) async throws(TimelineError) { throw .unavailable }
  func setPinned(_ pinned: Bool, eventId: String) async throws(TimelineError) { throw .unavailable }
  func pinnedMessages() async -> [TimelineMessage] { [] }
  func loadDraft() async -> String? { nil }
  func report(eventId: String, reason: String?) async throws(TimelineError) { throw .unavailable }
  func retrySend(transactionId: String) async {}
  func retryDecryption(sessionIds: [String]) async {}
  func discardUnsent(transactionId: String) async throws(TimelineError) { throw .unavailable }
  func ignore(userId: String) async throws(TimelineError) { throw .unavailable }
  func saveDraft(_ text: String) async {}
  func forward(eventId: String, to roomId: String) async throws(TimelineError) {
    throw .unavailable
  }
  func typingMembers() async -> AsyncStream<[String]> { AsyncStream { $0.finish() } }
  func reply(text: String, to eventId: String) async throws(TimelineError) { throw .unavailable }
  func edit(eventId: String, text: String) async throws(TimelineError) { throw .unavailable }
  func redact(eventId: String) async throws(TimelineError) { throw .unavailable }
  func toggleReaction(_ key: String, on eventId: String) async throws(TimelineError) {
    throw .unavailable
  }
  func markAsRead() async {}
  func close() async {}
}

struct UnavailableMedia: MediaRepository {
  func thumbnail(_ media: MediaReference, width: Int, height: Int) async throws(MediaError) -> Data
  {
    throw .notSignedIn
  }
  func content(_ media: MediaReference) async throws(MediaError) -> Data { throw .notSignedIn }
  func file(_ media: MediaReference, filename: String) async throws(MediaError) -> URL {
    throw .notSignedIn
  }
}

struct UnavailableAccountSettings: AccountSettingsRepository {
  func displayName() async throws(SettingsError) -> String? { nil }
  func setDisplayName(_ name: String) async throws(SettingsError) { throw .notSignedIn }
  func setAvatar(_ picture: PictureUpload) async throws(SettingsError) { throw .notSignedIn }
  func removeAvatar() async throws(SettingsError) { throw .notSignedIn }
  func avatar() async -> MediaReference? { nil }
  func blockedUsers() async throws(SettingsError) -> [BlockedUser] { [] }
  func unblock(userId: String) async throws(SettingsError) { throw .notSignedIn }
  func recoveryStatus() async -> RecoveryStatus { .unknown }
  func recover(recoveryKey: String) async throws(SettingsError) { throw .notSignedIn }
  func enableRecovery() async throws(SettingsError) -> String { throw .notSignedIn }
  func defaultNotificationMode(isDirect: Bool) async -> NotificationMode { .allMessages }
  func setDefaultNotificationMode(_ mode: NotificationMode, isDirect: Bool)
    async throws(SettingsError)
  {
    throw .notSignedIn
  }
}

struct UnavailablePeople: PeopleRepository {
  func search(_ text: String) async throws(PeopleError) -> [Person] { throw .notSignedIn }
  func directChat(with userId: String) async throws(PeopleError) -> String { throw .notSignedIn }
  func createGroup(name: String, inviting userIds: [String]) async throws(PeopleError) -> String {
    throw .notSignedIn
  }
}
