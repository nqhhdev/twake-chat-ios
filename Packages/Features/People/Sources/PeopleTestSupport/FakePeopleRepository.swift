import Domain
import Foundation

/// A hand-written `PeopleRepository` for tests (ADR 0010).
public final class FakePeopleRepository: PeopleRepository, @unchecked Sendable {
  private let lock = NSLock()
  private var _people: [Person] = []
  private var _searches: [String] = []
  private var _created: [(name: String, userIds: [String])] = []
  private var _directs: [String] = []
  private var _fails = false

  public init() {}

  public var people: [Person] {
    get { lock.withLock { _people } }
    set { lock.withLock { _people = newValue } }
  }
  public var fails: Bool {
    get { lock.withLock { _fails } }
    set { lock.withLock { _fails = newValue } }
  }
  public var searches: [String] { lock.withLock { _searches } }
  public var directs: [String] { lock.withLock { _directs } }
  public var createdGroups: [(name: String, userIds: [String])] { lock.withLock { _created } }

  public func search(_ text: String) async throws(PeopleError) -> [Person] {
    lock.withLock { _searches.append(text) }
    if fails { throw .requestFailed }
    return people.filter { $0.name.localizedCaseInsensitiveContains(text) || $0.id.contains(text) }
  }

  public func directChat(with userId: String) async throws(PeopleError) -> String {
    if fails { throw .requestFailed }
    lock.withLock { _directs.append(userId) }
    return "!dm-\(userId)"
  }

  public func createGroup(name: String, inviting userIds: [String]) async throws(PeopleError)
    -> String
  {
    if fails { throw .requestFailed }
    lock.withLock { _created.append((name, userIds)) }
    return "!group"
  }
}
