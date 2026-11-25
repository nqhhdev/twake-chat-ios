import Domain
import SwiftUI

enum ComposerKey: Equatable {
  case send
  case newLine
  case editLast
  case cancel

  init?(_ key: KeyEquivalent, modifiers: EventModifiers) {
    let modifiers = modifiers.subtracting([.capsLock, .numericPad])
    switch key {
    case .return where modifiers.isEmpty: self = .send
    case .return where modifiers == .shift || modifiers == .option: self = .newLine
    case .upArrow where modifiers.isEmpty: self = .editLast
    case .escape where modifiers.isEmpty: self = .cancel
    default: return nil
    }
  }
}

extension RoomViewModel {
  func handle(_ key: ComposerKey) -> Bool {
    switch key {
    case .send:
      guard canSend else { return true }
      Task { await send() }
      return true
    case .newLine:
      return false
    case .editLast:
      guard draft.isEmpty, composerMode == .new, let message = lastEditableMessage else {
        return false
      }
      edit(message)
      return true
    case .cancel:
      guard composerMode != .new else { return false }
      cancelComposerMode()
      return true
    }
  }

  var lastEditableMessage: TimelineMessage? {
    guard case .loaded(let items) = state else { return nil }
    for item in items.reversed() {
      guard case .message(let message) = item.kind, message.isOwn, message.eventId != nil else {
        continue
      }
      if case .text = message.body { return message }
    }
    return nil
  }
}
