import SwiftUI
import Testing

@testable import TwakeChat

@MainActor
struct RootViewTests {
  @Test func bodyIsAnEmptyColor() {
    let body = RootView().body
    #expect(type(of: body) == Color.self)
  }
}
