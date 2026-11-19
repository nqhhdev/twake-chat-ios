import Domain
import Foundation
import SwiftUI

/// Creating, voting in and ending polls.
extension RoomViewModel {
  /// Sends the poll the user wrote; `false` (with a message) when it failed, so the sheet stays open.
  @discardableResult
  public func createPoll(_ draft: PollDraft) async -> Bool {
    guard draft.canSend else { return false }
    errorMessage = nil
    do {
      try await repository.createPoll(draft)
      sendCount += 1
      return true
    } catch {
      errorMessage = "Could not send the poll."
      return false
    }
  }

  /// Votes for `answerId` in a poll that has not ended, or takes the vote back in a multiple-choice poll.
  public func vote(_ answerId: String, in message: TimelineMessage) async {
    guard let poll = message.poll, !poll.isEnded, let eventId = message.eventId else { return }
    do {
      try await repository.vote(poll.selection(tapping: answerId), in: eventId)
    } catch {
      errorMessage = "Could not send your vote."
    }
  }

  /// The user may end this poll: they created it and it is still open.
  public func canEndPoll(_ message: TimelineMessage) -> Bool {
    message.isOwn && message.eventId != nil && message.poll.map { !$0.isEnded } == true
  }

  public func endPoll(_ message: TimelineMessage) async {
    guard canEndPoll(message), let eventId = message.eventId else { return }
    do {
      try await repository.endPoll(eventId)
    } catch {
      errorMessage = "Could not end the poll."
    }
  }
}
