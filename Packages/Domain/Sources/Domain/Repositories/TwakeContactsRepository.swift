import Foundation

public struct TwakeContactsFeatures: Sendable, Equatable {
  public let addressBook: Bool
  public let invitations: Bool

  public init(addressBook: Bool, invitations: Bool) {
    self.addressBook = addressBook
    self.invitations = invitations
  }

  public static let none = TwakeContactsFeatures(addressBook: false, invitations: false)
}

public struct AddressBookEntry: Sendable, Equatable, Hashable, Identifiable {
  public let id: String
  public let userId: String
  public let displayName: String
  public let active: Bool

  public init(id: String, userId: String, displayName: String, active: Bool = true) {
    self.id = id
    self.userId = userId
    self.displayName = displayName
    self.active = active
  }

  public var name: String { displayName.isEmpty ? userId : displayName }

  public static func isUserId(_ text: String) -> Bool {
    text.wholeMatch(of: /@[^:\s]+:[^\s]+/) != nil
  }
}

public struct TwakeInvitation: Sendable, Equatable, Identifiable {
  public enum Status: Sendable, Equatable {
    case joined(userId: String)
    case opened
    case pending
    case expired
  }

  public let id: String
  public let recipient: String
  public let kind: LinkedAddress.Kind?
  public let expiration: Date?
  public let accessed: Bool
  public let userId: String?

  public init(
    id: String, recipient: String, kind: LinkedAddress.Kind?, expiration: Date?, accessed: Bool,
    userId: String?
  ) {
    self.id = id
    self.recipient = recipient
    self.kind = kind
    self.expiration = expiration
    self.accessed = accessed
    self.userId = userId
  }

  public func status(now: Date = .now) -> Status {
    if let userId, !userId.isEmpty { return .joined(userId: userId) }
    if let expiration, expiration < now { return .expired }
    return accessed ? .opened : .pending
  }
}

public struct InvitationLink: Sendable, Equatable {
  public let id: String
  public let url: URL

  public init(id: String, url: URL) {
    self.id = id
    self.url = url
  }
}

public enum TwakeContactsError: Error, Sendable, Equatable {
  case notSignedIn
  case unavailable
  case invalid
  case tooManyRequests
  case requestFailed
}

public protocol TwakeContactsRepository: Sendable {
  func features() async -> TwakeContactsFeatures

  func addressBook() async throws(TwakeContactsError) -> [AddressBookEntry]

  func addContact(userId: String, displayName: String) async throws(TwakeContactsError)
    -> [AddressBookEntry]

  func updateContact(_ entry: AddressBookEntry, displayName: String)
    async throws(TwakeContactsError)
    -> AddressBookEntry

  func removeContact(_ entry: AddressBookEntry) async throws(TwakeContactsError)

  func sendInvitation(to address: ContactAddress) async throws(TwakeContactsError) -> String

  func invitationLink(for address: ContactAddress?) async throws(TwakeContactsError)
    -> InvitationLink

  func invitations() async throws(TwakeContactsError) -> [TwakeInvitation]

  func invitation(id: String) async throws(TwakeContactsError) -> TwakeInvitation
}
