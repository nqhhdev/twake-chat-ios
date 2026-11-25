import Foundation

public struct IdentityPolicy: Sendable, Equatable, Hashable, Identifiable {
  public let id: String
  public let title: String
  public let url: URL

  public init(id: String, title: String, url: URL) {
    self.id = id
    self.title = title
    self.url = url
  }
}

public enum IdentityServerStatus: Sendable, Equatable {
  case unavailable
  case needsConsent(server: String, policies: [IdentityPolicy])
  case ready
}

public enum IdentityError: Error, Sendable, Equatable {
  case notSignedIn
  case unavailable
  case termsNotAccepted
  case requestFailed
}

public protocol IdentityRepository: Sendable {
  func status() async -> IdentityServerStatus

  func acceptTerms(_ policies: [IdentityPolicy]) async throws(IdentityError)

  func lookup(_ addresses: [ContactAddress]) async throws(IdentityError) -> [ContactAddress: String]

  func invite(_ address: ContactAddress, roomId: String) async throws(IdentityError)

  func startDirectChat(inviting address: ContactAddress) async throws(IdentityError) -> String
}

public struct AddressBookContact: Sendable, Equatable, Identifiable {
  public let id: String
  public let name: String
  public let emails: [String]
  public let phones: [String]

  public init(id: String, name: String, emails: [String], phones: [String]) {
    self.id = id
    self.name = name
    self.emails = emails
    self.phones = phones
  }

  public func addresses(regionCode: String?) -> [ContactAddress] {
    var seen = Set<ContactAddress>()
    return
      (emails.compactMap(ContactAddress.email)
      + phones.compactMap { ContactAddress.phone($0, regionCode: regionCode) })
      .filter { seen.insert($0).inserted }
  }
}

public enum AddressBookAccess: Sendable, Equatable {
  case notDetermined
  case granted
  case denied
}

public protocol AddressBook: Sendable {
  func access() async -> AddressBookAccess

  func requestAccess() async -> Bool

  func contacts() async -> [AddressBookContact]
}
