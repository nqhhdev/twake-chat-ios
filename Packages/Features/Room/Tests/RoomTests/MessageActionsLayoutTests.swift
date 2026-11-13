import Foundation
import Testing

@testable import Room

/// The long-press layer keeps the bubble whole and the menu on screen (the owner's "bubble was cut" and "more
/// options" on the folded Duo, 678 pt tall).
struct MessageActionsLayoutTests {
  private let height: CGFloat = 678

  @Test func aShortMessageKeepsItsSizeAndPlace() {
    let layout = MessageActionsOverlay.layout(
      rowTop: 300, rowHeight: 60, screenHeight: height, actionCount: 4)
    #expect(layout.previewScale == 1)
    #expect(!layout.scrollsMenu)
    // The tapback bar sits right above the row: 52 pt bar and an 8 pt gap.
    #expect(abs(layout.top - 240) < 0.5)
  }

  @Test func aTallAlbumShrinksToFitInsteadOfBeingCut() {
    let layout = MessageActionsOverlay.layout(
      rowTop: 100, rowHeight: 520, screenHeight: height, actionCount: 4)
    #expect(layout.previewScale < 1)
    let total = 52 + layout.previewHeight + layout.menuHeight + 16
    #expect(layout.top >= 8)
    #expect(layout.top + total <= height - 8 + 0.5)
  }

  @Test func manyActionsScrollInsideTheMenu() {
    let layout = MessageActionsOverlay.layout(
      rowTop: 300, rowHeight: 60, screenHeight: height, actionCount: 12)
    #expect(layout.scrollsMenu)
    #expect(layout.menuHeight < 12 * 44)
  }

  @Test func aMessageNearTheBottomMovesUpSoTheMenuFits() {
    let layout = MessageActionsOverlay.layout(
      rowTop: 600, rowHeight: 60, screenHeight: height, actionCount: 6)
    #expect(layout.top + 52 + 60 + layout.menuHeight + 16 <= height - 8 + 0.5)
  }
}
