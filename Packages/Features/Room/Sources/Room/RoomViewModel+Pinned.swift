import Domain
import Foundation
import SwiftUI

/// The room's pinned messages and the banner above the timeline.
extension RoomViewModel {
  /// The pinned message the banner shows now.
  public var currentPinned: TimelineMessage? {
    pinned.isEmpty ? nil : pinned[min(pinnedIndex, pinned.count - 1)]
  }

  public func loadPinned() async {
    pinned = await repository.pinnedMessages()
    pinnedIndex = max(0, pinned.count - 1)
  }

  /// The banner's tap: show the pin before this one, wrapping round, as Telegram cycles its pins.
  public func showPreviousPinned() {
    guard !pinned.isEmpty else { return }
    pinnedIndex = pinnedIndex == 0 ? pinned.count - 1 : pinnedIndex - 1
  }

  public func isPinned(_ message: TimelineMessage) -> Bool {
    pinned.contains { $0.eventId != nil && $0.eventId == message.eventId }
  }

  public func togglePin(_ message: TimelineMessage) async {
    guard let eventId = message.eventId else { return }
    let pin = !isPinned(message)
    do {
      try await repository.setPinned(pin, eventId: eventId)
      await loadPinned()
      showToast(pin ? localized("Pinned") : localized("Unpinned"))
    } catch {
      errorMessage = localized("Could not pin the message.")
    }
  }
}
