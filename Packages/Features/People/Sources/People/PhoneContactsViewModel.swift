import Domain
import Foundation
import Observation

@MainActor @Observable
public final class PhoneContactsViewModel {
  public enum State: Equatable {
    case hidden
    case askPermission
    case denied
    case needsConsent(IdentityConsent)
    case loading
    case loaded
    case failed
  }

  public struct Entry: Equatable, Identifiable, Sendable {
    public let contact: AddressBookContact
    public let address: ContactAddress
    public let userId: String?

    public var id: String { "\(contact.id)|\(address.id)" }
  }

  public private(set) var state: State = .hidden
  public private(set) var onMatrix: [Entry] = []
  public private(set) var invitable: [Entry] = []

  @ObservationIgnored public var regionCode: String? = Locale.current.region?.identifier
  @ObservationIgnored private let addressBook: any AddressBook
  @ObservationIgnored private let identity: (any IdentityRepository)?

  public init(addressBook: any AddressBook, identity: (any IdentityRepository)?) {
    self.addressBook = addressBook
    self.identity = identity
  }

  public func load() async {
    guard let identity, state != .loading else { return }
    let status = await identity.status()
    guard status != .unavailable else {
      state = .hidden
      return
    }
    switch await addressBook.access() {
    case .notDetermined:
      state = .askPermission
    case .denied:
      state = .denied
    case .granted:
      if case .needsConsent(let server, let policies) = status {
        state = .needsConsent(IdentityConsent(server: server, policies: policies))
      } else {
        await match(identity)
      }
    }
  }

  public func allowAccess() async {
    guard state == .askPermission else { return }
    state = await addressBook.requestAccess() ? .hidden : .denied
    if state == .hidden { await load() }
  }

  public func acceptConsent() async {
    guard case .needsConsent(let consent) = state, let identity else { return }
    state = .loading
    do {
      try await identity.acceptTerms(consent.policies)
    } catch {
      state = .needsConsent(consent)
      return
    }
    await match(identity)
  }

  public func filtered(_ entries: [Entry], by query: String) -> [Entry] {
    let text = query.trimmingCharacters(in: .whitespaces)
    guard !text.isEmpty else { return entries }
    return entries.filter {
      $0.contact.name.localizedStandardContains(text)
        || $0.address.address.localizedStandardContains(text)
    }
  }

  private func match(_ identity: any IdentityRepository) async {
    state = .loading
    let contacts = await addressBook.contacts()
    let pairs = contacts.flatMap { contact in
      contact.addresses(regionCode: regionCode).map { (contact, $0) }
    }
    let found: [ContactAddress: String]
    do {
      found = try await identity.lookup(pairs.map(\.1))
    } catch {
      state = .failed
      return
    }
    var matched: [Entry] = []
    var seenUsers = Set<String>()
    for (contact, address) in pairs {
      guard let userId = found[address], seenUsers.insert(userId).inserted else { continue }
      matched.append(Entry(contact: contact, address: address, userId: userId))
    }
    var handled = Set(matched.map(\.contact.id))
    var others: [Entry] = []
    for (contact, address) in pairs {
      guard handled.insert(contact.id).inserted else { continue }
      others.append(Entry(contact: contact, address: address, userId: nil))
    }
    onMatrix = matched.sorted {
      $0.contact.name.localizedCompare($1.contact.name) == .orderedAscending
    }
    invitable = others.sorted {
      $0.contact.name.localizedCompare($1.contact.name) == .orderedAscending
    }
    state = .loaded
  }
}
