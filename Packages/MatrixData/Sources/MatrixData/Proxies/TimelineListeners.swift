import Domain
import Foundation
import MatrixRustSDK

actor IndexRecorder {
  private let index: MessageIndex
  private var recorded: [String: String] = [:]

  init(index: MessageIndex) {
    self.index = index
  }

  func record(roomId: String, items: [Domain.TimelineItem]) async {
    let (entries, redacted) = MessageIndex.entries(roomId: roomId, items: items)
    let changed = entries.filter { recorded[$0.eventId] != $0.text }
    let removed = redacted.filter { recorded[$0] != "" }
    for entry in changed { recorded[entry.eventId] = entry.text }
    for eventId in removed { recorded[eventId] = "" }
    await index.record(changed)
    await index.remove(eventIds: removed)
  }
}
final class SendHandles: @unchecked Sendable {
  private let lock = NSLock()
  private var handles: [String: SendHandle] = [:]

  func note(_ item: MatrixRustSDK.TimelineItem) {
    guard let event = item.asEvent(), event.isOwn,
      case .transactionId(let id) = event.eventOrTransactionId,
      case .sendingFailed = event.localSendState,
      let handle = event.lazyProvider.getSendHandle()
    else { return }
    lock.withLock { handles[id] = handle }
  }

  func handle(of transactionId: String) -> SendHandle? {
    lock.withLock { handles[transactionId] }
  }
}

final class DiffListener: TimelineListener {
  private let diffs: AsyncStream<[TimelineDiff]>.Continuation

  init(_ diffs: AsyncStream<[TimelineDiff]>.Continuation) {
    self.diffs = diffs
  }

  func onUpdate(diff: [TimelineDiff]) {
    diffs.yield(diff)
  }
}

actor IdentityStates {
  private var violations: [String: IdentityWarning.Kind] = [:]

  func apply(_ changes: [IdentityStatusChange]) -> [String: IdentityWarning.Kind] {
    for change in changes {
      switch change.changedTo {
      case .pinViolation: violations[change.userId] = .changed
      case .verificationViolation: violations[change.userId] = .verifiedChanged
      default: violations[change.userId] = nil
      }
    }
    return violations
  }
}

final class IdentityListener: IdentityStatusChangeListener {
  private let onChange: @Sendable ([IdentityStatusChange]) -> Void

  init(_ onChange: @escaping @Sendable ([IdentityStatusChange]) -> Void) {
    self.onChange = onChange
  }

  func call(identityStatusChange: [IdentityStatusChange]) {
    onChange(identityStatusChange)
  }
}

final class TypingListener: TypingNotificationsListener {
  private let onChange: @Sendable ([String]) -> Void

  init(_ onChange: @escaping @Sendable ([String]) -> Void) {
    self.onChange = onChange
  }

  func call(typingUserIds: [String]) {
    onChange(typingUserIds)
  }
}
