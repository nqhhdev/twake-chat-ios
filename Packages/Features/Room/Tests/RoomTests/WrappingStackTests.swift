import CoreGraphics
import Testing

@testable import Room

@MainActor
struct WrappingStackTests {
  @Test func childrenThatFitShareOneRow() {
    #expect(WrappingStack.rows(of: [40, 40, 40], maxWidth: 200, spacing: 4) == [[0, 1, 2]])
  }

  @Test func aChildThatDoesNotFitStartsANewRow() {
    #expect(
      WrappingStack.rows(of: [60, 60, 60, 60], maxWidth: 130, spacing: 4) == [[0, 1], [2, 3]])
  }

  @Test func aChildWiderThanTheRowGetsARowOfItsOwn() {
    #expect(WrappingStack.rows(of: [30, 300, 30], maxWidth: 100, spacing: 4) == [[0], [1], [2]])
  }
}
