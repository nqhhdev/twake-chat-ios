import Foundation

/// How a chat shows room events, as the Flutter app's Chat settings choose (`SettingsChatView`): both kinds are hidden
/// by default, as there.
public struct ChatDisplaySettings: Sendable, Equatable {
  /// Hides room setting changes, such as encryption, the description or the permissions.
  public var hidesUnimportantEvents: Bool
  /// Hides events the app cannot show.
  public var hidesUnknownEvents: Bool

  public init(hidesUnimportantEvents: Bool = true, hidesUnknownEvents: Bool = true) {
    self.hidesUnimportantEvents = hidesUnimportantEvents
    self.hidesUnknownEvents = hidesUnknownEvents
  }

  public func shows(_ item: TimelineItem) -> Bool {
    switch item.visibility {
    case .always: true
    case .unimportant: !hidesUnimportantEvents
    case .unknown: !hidesUnknownEvents
    }
  }

  /// The items a chat draws: the hidden events left out, and with them a day divider that has nothing left under it.
  public func visible(_ items: [TimelineItem]) -> [TimelineItem] {
    let shown = items.filter { shows($0) }
    guard shown.count != items.count else { return items }
    return shown.enumerated().compactMap { index, item in
      guard case .dayDivider = item.kind else { return item }
      let next = shown[(index + 1)...].first { $0.kind != .readMarker }
      if let next, case .dayDivider = next.kind { return nil }
      return next == nil ? nil : item
    }
  }
}

/// Where this device keeps the chat display settings. Implemented in AppShared.
public protocol ChatDisplaySettingsStore: Sendable {
  func load() -> ChatDisplaySettings
  func save(_ settings: ChatDisplaySettings)
}
