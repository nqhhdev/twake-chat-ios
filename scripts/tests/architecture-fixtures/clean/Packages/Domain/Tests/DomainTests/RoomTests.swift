import Foundation
import Testing

@testable import Domain

@Test func roomKeepsItsID() {
  let id = UUID()
  #expect(Room(id: id).id == id)
}
