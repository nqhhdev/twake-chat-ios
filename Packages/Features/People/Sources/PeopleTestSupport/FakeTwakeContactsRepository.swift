import Domain
import Foundation

public final class FakeTwakeContactsRepository: TwakeContactsRepository, @unchecked Sendable {
  private let lock = NSLock()
  private var _features: TwakeContactsFeatures
  private var _entries: [AddressBookEntry] = []
  private var _invitations: [TwakeInvitation] = []
  private var _sent: [ContactAddress] = []
  private var _links: [ContactAddress?] = []
  private var _failure: TwakeContactsError?
  private var _nextId = 0

  public init(features: TwakeContactsFeatures = .init(addressBook: true, invitations: true)) {
    _features = features
  }

  public var entries: [AddressBookEntry] {
    get { lock.withLock { _entries } }
    set { lock.withLock { _entries = newValue } }
  }
  public var storedInvitations: [TwakeInvitation] {
    get { lock.withLock { _invitations } }
    set { lock.withLock { _invitations = newValue } }
  }
  public var failure: TwakeContactsError? {
    get { lock.withLock { _failure } }
    set { lock.withLock { _failure = newValue } }
  }
  public var sent: [ContactAddress] { lock.withLock { _sent } }
  public var links: [ContactAddress?] { lock.withLock { _links } }

  public func features() async -> TwakeContactsFeatures { lock.withLock { _features } }

  public func addressBook() async throws(TwakeContactsError) -> [AddressBookEntry] {
    try check()
    return entries
  }

  public func addContact(userId: String, displayName: String) async throws(TwakeContactsError)
    -> [AddressBookEntry]
  {
    try check()
    return lock.withLock {
      _nextId += 1
      _entries.append(AddressBookEntry(id: "c\(_nextId)", userId: userId, displayName: displayName))
      return _entries
    }
  }

  public func updateContact(_ entry: AddressBookEntry, displayName: String)
    async throws(TwakeContactsError) -> AddressBookEntry
  {
    try check()
    let updated = AddressBookEntry(
      id: entry.id, userId: entry.userId, displayName: displayName, active: entry.active)
    lock.withLock { _entries = _entries.map { $0.id == entry.id ? updated : $0 } }
    return updated
  }

  public func removeContact(_ entry: AddressBookEntry) async throws(TwakeContactsError) {
    try check()
    lock.withLock { _entries.removeAll { $0.id == entry.id } }
  }

  public func sendInvitation(to address: ContactAddress) async throws(TwakeContactsError)
    -> String
  {
    try check()
    return lock.withLock {
      _sent.append(address)
      return "inv\(_sent.count)"
    }
  }

  public func invitationLink(for address: ContactAddress?) async throws(TwakeContactsError)
    -> InvitationLink
  {
    try check()
    lock.withLock { _links.append(address) }
    return InvitationLink(id: "link1", url: URL(string: "https://chat.example.org/?invite=link1")!)
  }

  public func invitations() async throws(TwakeContactsError) -> [TwakeInvitation] {
    try check()
    return storedInvitations
  }

  public func invitation(id: String) async throws(TwakeContactsError) -> TwakeInvitation {
    try check()
    guard let found = storedInvitations.first(where: { $0.id == id }) else {
      throw .requestFailed
    }
    return found
  }

  private func check() throws(TwakeContactsError) {
    if let failure { throw failure }
  }
}
