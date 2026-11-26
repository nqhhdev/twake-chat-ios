public protocol ServerCapabilitiesRepository: Sendable {
  func current() async -> ServerCapabilities
  @discardableResult func refresh() async -> ServerCapabilities
}
