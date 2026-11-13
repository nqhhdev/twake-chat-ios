import Testing

@testable import TwakeChat

/// The chat list sits beside the chat from 905 pt (ADR 0022); the tabs are the system tab view on every screen.
struct ChatShellLayoutTests {
  @Test func aPhoneHeldUprightHasOneColumn() {
    #expect(!ChatShell.Layout(width: 390).isTwoColumn)
  }

  @Test func aFoldedDuoHasOneColumn() {
    #expect(!ChatShell.Layout(width: 466).isTwoColumn)
  }

  @Test func anUnfoldedDuoHasTwoColumns() {
    #expect(ChatShell.Layout(width: 951).isTwoColumn)
  }

  @Test func anUnfoldedDuoHeldUprightHasOneColumn() {
    #expect(!ChatShell.Layout(width: 669).isTwoColumn)
  }

  @Test func aPhoneOnItsSideHasOneColumn() {
    #expect(!ChatShell.Layout(width: 844).isTwoColumn)
  }

  @Test func anIPadHasTwoColumns() {
    #expect(ChatShell.Layout(width: 1024).isTwoColumn)
  }
}
