import Domain
import Foundation
import SwiftUI

/// Paging older history and jumping to a message or a day in the timeline.
extension RoomViewModel {
  /// Loads one older page. Returns `false` only when the page failed; a call while a page is loading, or at the start
  /// of the room, does nothing and returns `true`.
  @discardableResult
  public func loadOlder() async -> Bool {
    guard !isLoadingOlder, !reachedStart else { return true }
    isLoadingOlder = true
    defer { isLoadingOlder = false }
    do {
      reachedStart = try await repository.loadOlder()
      return true
    } catch {
      // Scrolling up again tries once more.
      return false
    }
  }

  /// One approach of the top of the timeline loads one page. Leaving the top re-arms the trigger. A call while a page
  /// is already loading, or at the start of the room, does nothing.
  public func topZoneChanged(isNearTop: Bool) async {
    if !isNearTop {
      topArmed = true
      return
    }
    guard topArmed, !isLoadingOlder, !reachedStart, !isHistoryPaused else { return }
    topArmed = false
    await loadOlder()
  }

  /// Loads older pages to fill a timeline that is shorter than the viewport, or that has nothing to show yet, until
  /// the start of the room or the limits of `historyLoading`. A long room is not filled this way: the user scrolls
  /// to the top for each next page (`topZoneChanged`).
  public func loadOlderWhileVisible() async {
    var pages = 0
    var failures = 0
    while !reachedStart, !Task.isCancelled {
      guard pages < historyLoading.maxAutomaticPages, failures < historyLoading.maxFailures else {
        isHistoryPaused = true
        return
      }
      if isLoadingOlder {
        // A page is on its way (the one asked when the chat opened, or a jump): wait for it. Counting it as a page
        // paused a slow room after a few seconds with nothing loaded.
        try? await Task.sleep(for: historyLoading.pause)
        continue
      }
      if await loadOlder() {
        pages += 1
        failures = 0
      } else {
        failures += 1
      }
      try? await Task.sleep(
        for: failures == 0 ? historyLoading.pause : historyLoading.pauseAfterFailure)
    }
  }

  /// What the timeline shows in place of messages while it has none, so the screen is never blank.
  public enum Placeholder: Equatable, Sendable {
    /// Older pages are loading.
    case loading
    /// Loading stopped by itself; the user asks for more.
    case paused
  }

  /// `nil` once a message shows or the start of the room is reached (the empty-chat card takes over there).
  public var placeholder: Placeholder? {
    guard case .loaded = state, !reachedStart else { return nil }
    let hasMessage = rows.contains { row in
      switch row {
      case .message, .album: true
      case .other, .notices: false
      }
    }
    if hasMessage { return nil }
    return isHistoryPaused ? .paused : .loading
  }

  /// The user asked for earlier messages after loading paused: one page, not another automatic run.
  public func resumeHistory() async {
    isHistoryPaused = false
    topArmed = false
    await loadOlder()
  }

  /// Keeps `reachedStart` true to the list on screen. The SDK empties and refills a timeline after a gap in sync; the
  /// refilled list no longer holds the start of the room, and without this the room stayed empty with nothing asking
  /// for older messages.
  func noteStart(in list: [TimelineItem]) {
    if list.contains(where: { $0.kind == .timelineStart }) {
      reachedStart = true
      sawTimelineStart = true
    } else if sawTimelineStart {
      sawTimelineStart = false
      reachedStart = false
      isHistoryPaused = false
    }
  }

  /// The timeline item id of the message `eventId`, or `nil` when it is not loaded.
  func itemId(ofEvent eventId: String) -> String? {
    guard case .loaded(let items) = state else { return nil }
    return items.first {
      if case .message(let message) = $0.kind { message.eventId == eventId } else { false }
    }?.id
  }

  /// How many older pages a jump loads looking for its message before giving up.
  public static let maxPagesToFind = 10

  /// Scrolls to a message and flashes it, loading older messages first when it is not loaded yet, as far as
  /// `maxPages` pages (a search result may be further back than a reply).
  public func jump(toEvent eventId: String, maxPages: Int = maxPagesToFind) async {
    var pages = 0
    while rowId(containingEvent: eventId) == nil {
      // Not loaded yet: load older pages, as far as `maxPagesToFind`, as the Flutter app does for a reply.
      guard !reachedStart, pages < maxPages, await loadOlder() else {
        showToast("Could not find that message")
        return
      }
      pages += 1
      // The page reaches `rows` through the timeline stream, a moment after `loadOlder` returns.
      for _ in 0..<20 where rowId(containingEvent: eventId) == nil {
        try? await Task.sleep(for: .milliseconds(50))
      }
    }
    guard let id = rowId(containingEvent: eventId) else { return }
    scrollTarget = id
    highlightedEventId = eventId
    Task { [weak self] in
      try? await Task.sleep(for: .seconds(1.6))
      if self?.highlightedEventId == eventId { self?.highlightedEventId = nil }
    }
  }

  /// Scrolls to the first message sent on `date`'s day or later, loading older pages until the timeline reaches that
  /// day (at most `maxPages`). Works in encrypted chats, since it reads the decrypted timeline.
  public func jump(toDate date: Date, calendar: Calendar = .current, maxPages: Int = 200) async {
    let day = calendar.startOfDay(for: date)
    var pages = 0
    while !reachedStart, pages < maxPages, oldestMessageDate.map({ $0 >= day }) ?? true {
      guard await loadOlder() else { break }
      pages += 1
      try? await Task.sleep(for: .milliseconds(120))
    }
    guard let target = firstMessage(onOrAfter: day), let eventId = target.eventId else {
      showToast("No messages from that day")
      return
    }
    await jump(toEvent: eventId, maxPages: 0)
  }

  /// Scrolls to the room's first message, loading older pages until the start of the room (web: "Jump to start").
  public func jumpToStart() async {
    await jump(toDate: .distantPast)
  }

  /// The date of the oldest loaded message.
  var oldestMessageDate: Date? {
    guard case .loaded(let items) = state else { return nil }
    return items.lazy.compactMap { item -> Date? in
      if case .message(let message) = item.kind { message.date } else { nil }
    }.first
  }

  /// The first loaded message sent at or after `day`.
  func firstMessage(onOrAfter day: Date) -> TimelineMessage? {
    guard case .loaded(let items) = state else { return nil }
    for item in items {
      if case .message(let message) = item.kind, message.date >= day, message.eventId != nil {
        return message
      }
    }
    return nil
  }

  /// The row that shows `eventId`: its own, or the album it belongs to.
  private func rowId(containingEvent eventId: String) -> String? {
    for row in rows {
      switch row {
      case .message(let model) where model.message.eventId == eventId: return row.id
      case .album(let model) where model.messages.contains(where: { $0.eventId == eventId }):
        return row.id
      default: continue
      }
    }
    return nil
  }
}
