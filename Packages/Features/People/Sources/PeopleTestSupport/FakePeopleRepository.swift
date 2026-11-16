import Domain
import Foundation

/// A hand-written `PeopleRepository` for tests (ADR 0010).
public final class FakePeopleRepository: PeopleRepository, @unchecked Sendable {
  private let lock = NSLock()
  private var _people: [Person] = []
  private var _searches: [String] = []
  private var _created: [(name: String, userIds: [String])] = []
  private var _directs: [String] = []
  private var _broadcasts: [(draft: BroadcastDraft, userIds: [String])] = []
  private var _fails = false
  private var _existing: [String: String] = [:]
  private var _started: [(userId: String, message: String)] = []

  public init() {}

  public var people: [Person] {
    get { lock.withLock { _people } }
    set { lock.withLock { _people = newValue } }
  }
  public var fails: Bool {
    get { lock.withLock { _fails } }
    set { lock.withLock { _fails = newValue } }
  }
  /// The direct chats that exist already, by user id.
  public var existingDirects: [String: String] {
    get { lock.withLock { _existing } }
    set { lock.withLock { _existing = newValue } }
  }
  public var startedDirects: [(userId: String, message: String)] { lock.withLock { _started } }
  public var searches: [String] { lock.withLock { _searches } }
  public var directs: [String] { lock.withLock { _directs } }
  public var createdGroups: [(name: String, userIds: [String])] { lock.withLock { _created } }
  public var createdBroadcasts: [(draft: BroadcastDraft, userIds: [String])] {
    lock.withLock { _broadcasts }
  }

  public func createBroadcast(_ draft: BroadcastDraft, inviting userIds: [String])
    async throws(PeopleError) -> String
  {
    if fails { throw .requestFailed }
    lock.withLock { _broadcasts.append((draft, userIds)) }
    return "!broadcast"
  }

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

  public func existingDirectChat(with userId: String) async -> String? {
    existingDirects[userId]
  }

  public func startDirectChat(with userId: String, firstMessage: String) async throws(PeopleError)
    -> String
  {
    if fails { throw .requestFailed }
    lock.withLock { _started.append((userId, firstMessage)) }
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
