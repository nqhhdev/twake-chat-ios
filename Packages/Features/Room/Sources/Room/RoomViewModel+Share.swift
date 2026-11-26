import Domain
import Foundation
import SwiftUI

extension RoomViewModel {
  public func receive(_ share: IncomingShare) {
    if case .loaded = state {
      Task { await apply(share) }
    } else {
      pendingShare = share
    }
  }

  func apply(_ share: IncomingShare) async {
    if let text = share.text, !text.isEmpty {
      draft = draft.isEmpty ? text : draft + "\n" + text
    }
    for file in share.files {
      guard let loaded = AttachmentLoader.load(document: file) else { continue }
      await send(
        attachment: loaded.kind, fileURL: loaded.fileURL, mimeType: loaded.mimeType,
        size: loaded.size)
      AttachmentLoader.remove(loaded)
    }
    share.done()
  }

  public func rejoin() async {
    guard isArchived, let rejoinRoom, !isRejoining else { return }
    isRejoining = true
    defer { isRejoining = false }
    errorMessage = nil
    if await rejoinRoom() {
      withAnimation { isArchived = false }
    } else {
      errorMessage = localized("Could not join this chat again. It may need an invitation.")
    }
  }
}

public struct IncomingShare {
  public let text: String?
  public let files: [URL]
  public let done: @MainActor () -> Void

  public init(text: String?, files: [URL], done: @escaping @MainActor () -> Void = {}) {
    self.text = text
    self.files = files
    self.done = done
  }
}
