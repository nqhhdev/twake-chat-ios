import Domain
import Foundation

public final class FakeIdentityRepository: IdentityRepository, @unchecked Sendable {
  private let lock = NSLock()
  private var _status: IdentityServerStatus = .ready
  private var _known: [ContactAddress: String] = [:]
  private var _lookups: [[ContactAddress]] = []
  private var _accepted: [[IdentityPolicy]] = []
  private var _invites: [(address: ContactAddress, roomId: String)] = []
  private var _directs: [ContactAddress] = []
  private var _failingInvites: Set<ContactAddress> = []
  private var _lookupFails = false

  public init() {}

  public var serverStatus: IdentityServerStatus {
    get { lock.withLock { _status } }
    set { lock.withLock { _status = newValue } }
  }
  public var known: [ContactAddress: String] {
    get { lock.withLock { _known } }
    set { lock.withLock { _known = newValue } }
  }
  public var failingInvites: Set<ContactAddress> {
    get { lock.withLock { _failingInvites } }
    set { lock.withLock { _failingInvites = newValue } }
  }
  public var lookupFails: Bool {
    get { lock.withLock { _lookupFails } }
    set { lock.withLock { _lookupFails = newValue } }
  }
  public var lookups: [[ContactAddress]] { lock.withLock { _lookups } }
  public var accepted: [[IdentityPolicy]] { lock.withLock { _accepted } }
  public var invites: [(address: ContactAddress, roomId: String)] { lock.withLock { _invites } }
  public var directs: [ContactAddress] { lock.withLock { _directs } }

  public func status() async -> IdentityServerStatus { serverStatus }

  public func acceptTerms(_ policies: [IdentityPolicy]) async throws(IdentityError) {
    lock.withLock {
      _accepted.append(policies)
      _status = .ready
    }
  }

  public func lookup(_ addresses: [ContactAddress]) async throws(IdentityError)
    -> [ContactAddress: String]
  {
    let (fails, status, known) = lock.withLock {
      _lookups.append(addresses)
      return (_lookupFails, _status, _known)
    }
    if fails { throw .requestFailed }
    guard status == .ready else { throw .termsNotAccepted }
    return known.filter { addresses.contains($0.key) }
  }

  public func invite(_ address: ContactAddress, roomId: String) async throws(IdentityError) {
    let fails = lock.withLock {
      _invites.append((address, roomId))
      return _failingInvites.contains(address)
    }
    if fails { throw .requestFailed }
  }

  public func startDirectChat(inviting address: ContactAddress) async throws(IdentityError)
    -> String
  {
    lock.withLock { _directs.append(address) }
    return "!direct-\(address.address):example.org"
  }
}

public final class FakeAddressBook: AddressBook, @unchecked Sendable {
  private let lock = NSLock()
  private var _access: AddressBookAccess
  private var _grants: Bool
  private var _entries: [AddressBookContact]
  private var _requests = 0

  public init(
    access: AddressBookAccess = .granted, grants: Bool = true, entries: [AddressBookContact] = []
  ) {
    _access = access
    _grants = grants
    _entries = entries
  }

  public var requests: Int { lock.withLock { _requests } }

  public func access() async -> AddressBookAccess { lock.withLock { _access } }

  public func requestAccess() async -> Bool {
    lock.withLock {
      _requests += 1
      _access = _grants ? .granted : .denied
      return _grants
    }
  }

  public func contacts() async -> [AddressBookContact] { lock.withLock { _entries } }
}
