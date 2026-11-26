import Foundation

struct CallIdentities {
  private var answered: UUID?
  private var aliases: [UUID: UUID] = [:]

  mutating func answer(_ systemId: UUID) {
    answered = systemId
  }

  mutating func start(_ appId: UUID) -> UUID? {
    guard let answered else { return nil }
    self.answered = nil
    aliases[appId] = answered
    return answered
  }

  func systemId(for appId: UUID) -> UUID {
    aliases[appId] ?? appId
  }

  func isAnswered(_ appId: UUID) -> Bool {
    aliases[appId] != nil
  }

  func appId(for systemId: UUID) -> UUID {
    aliases.first { $0.value == systemId }?.key ?? systemId
  }

  mutating func end(_ appId: UUID) {
    aliases.removeValue(forKey: appId)
  }

  mutating func takeAnswer() -> UUID? {
    defer { answered = nil }
    return answered
  }

  mutating func dropAnswer(_ systemId: UUID) {
    if answered == systemId { answered = nil }
  }
}
