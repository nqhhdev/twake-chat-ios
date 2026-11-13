import Testing

@testable import TwakeChat

/// The navigation adapts to the screen (ADR 0022): bottom bar on a phone held upright and on a folded Duo, rail on an
/// unfolded Duo, an iPad and any screen on its side.
struct ChatShellLayoutTests {
  @Test func aPhoneHeldUprightHasOneColumnAndTheBottomBar() {
    let layout = ChatShell.Layout(width: 390, height: 844)
    #expect(!layout.isTwoColumn)
    #expect(!layout.usesRail)
  }

  @Test func aFoldedDuoHasOneColumnAndTheBottomBar() {
    let layout = ChatShell.Layout(width: 466, height: 678)
    #expect(!layout.isTwoColumn)
    #expect(!layout.usesRail)
  }

  @Test func anUnfoldedDuoHasTwoColumnsAndTheRail() {
    let layout = ChatShell.Layout(width: 951, height: 669)
    #expect(layout.isTwoColumn)
    #expect(layout.usesRail)
  }

  @Test func anUnfoldedDuoHeldUprightHasOneColumnAndTheBottomBar() {
    let layout = ChatShell.Layout(width: 669, height: 951)
    #expect(!layout.isTwoColumn)
    #expect(!layout.usesRail)
  }

  @Test func aPhoneOnItsSideHasOneColumnAndTheRail() {
    let layout = ChatShell.Layout(width: 844, height: 390)
    #expect(!layout.isTwoColumn)
    #expect(layout.usesRail)
  }

  @Test func anIPadHasTwoColumnsAndTheRail() {
    let layout = ChatShell.Layout(width: 1024, height: 1366)
    #expect(layout.isTwoColumn)
    #expect(layout.usesRail)
  }
}
