import Foundation
import Testing

@testable import Room

struct CallIdentitiesTests {
  @Test func anAnsweredCallBecomesTheJoinedCall() {
    var identities = CallIdentities()
    let system = UUID()
    let app = UUID()
    identities.answer(system)
    #expect(identities.start(app) == system)
    #expect(identities.isAnswered(app))
    #expect(identities.systemId(for: app) == system)
    #expect(identities.appId(for: system) == app)
    identities.end(app)
    #expect(!identities.isAnswered(app))
    #expect(identities.systemId(for: app) == app)
  }

  @Test func aCallStartedWithoutAnAnswerKeepsItsOwnIdentity() {
    var identities = CallIdentities()
    let app = UUID()
    #expect(identities.start(app) == nil)
    #expect(identities.systemId(for: app) == app)
    #expect(identities.appId(for: app) == app)
  }

  @Test func anAnswerIsUsedOnce() {
    var identities = CallIdentities()
    let system = UUID()
    identities.answer(system)
    #expect(identities.start(UUID()) == system)
    #expect(identities.start(UUID()) == nil)
  }

  @Test func aPendingAnswerCanBeTakenOrDropped() {
    var identities = CallIdentities()
    let system = UUID()
    identities.answer(system)
    #expect(identities.takeAnswer() == system)
    #expect(identities.takeAnswer() == nil)
    identities.answer(system)
    identities.dropAnswer(UUID())
    identities.dropAnswer(system)
    #expect(identities.start(UUID()) == nil)
  }
}
