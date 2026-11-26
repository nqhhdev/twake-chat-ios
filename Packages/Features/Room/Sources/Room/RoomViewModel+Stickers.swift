import Domain
import Foundation

extension RoomViewModel {
  func loadStickerPacks() async {
    stickerPacks = await repository.stickerPacks()
  }

  public func send(sticker: Sticker) async {
    errorMessage = nil
    sendCount += 1
    do {
      try await repository.send(sticker: sticker)
    } catch {
      errorMessage = localized("Could not send the sticker. Please try again.")
    }
  }
}
