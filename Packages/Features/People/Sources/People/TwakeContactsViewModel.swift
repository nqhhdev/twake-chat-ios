import Domain
import Foundation
import Observation

@MainActor @Observable
public final class TwakeContactsViewModel {
  public private(set) var features: TwakeContactsFeatures = .none
  public private(set) var entries: [AddressBookEntry] = []
  public private(set) var invitations: [TwakeInvitation]?
  public private(set) var invited: [ContactAddress: String] = [:]
  public private(set) var link: InvitationLink?
  public private(set) var isWorking = false
  public private(set) var errorMessage: String?

  @ObservationIgnored private let repository: any TwakeContactsRepository

  public init(repository: any TwakeContactsRepository) {
    self.repository = repository
  }

  public func load() async {
    features = await repository.features()
    guard features.addressBook else {
      entries = []
      return
    }
    do {
      entries = Self.sorted(try await repository.addressBook())
    } catch {
      errorMessage = "Could not load your contacts."
    }
  }

  public func entry(forUserId userId: String) -> AddressBookEntry? {
    entries.first { $0.userId == userId }
  }

  public func filtered(by query: String) -> [AddressBookEntry] {
    let text = query.trimmingCharacters(in: .whitespaces)
    guard !text.isEmpty else { return entries }
    return entries.filter {
      $0.name.localizedStandardContains(text) || $0.userId.localizedStandardContains(text)
    }
  }

  public func add(userId: String, displayName: String) async -> Bool {
    let userId = userId.trimmingCharacters(in: .whitespacesAndNewlines)
    let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard AddressBookEntry.isUserId(userId) else {
      errorMessage = "Enter a Matrix ID such as @alice:example.org."
      return false
    }
    guard !name.isEmpty else {
      errorMessage = "Enter a name."
      return false
    }
    if entry(forUserId: userId) != nil {
      errorMessage = "\(userId) is already in your contacts."
      return false
    }
    return await work("Could not add the contact.") { () async throws(TwakeContactsError) in
      let list = try await self.repository.addContact(userId: userId, displayName: name)
      self.entries = Self.sorted(list)
    }
  }

  public func rename(_ entry: AddressBookEntry, to displayName: String) async -> Bool {
    let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty else {
      errorMessage = "Enter a name."
      return false
    }
    return await work("Could not change the contact.") { () async throws(TwakeContactsError) in
      let updated = try await self.repository.updateContact(entry, displayName: name)
      self.entries = Self.sorted(self.entries.map { $0.id == updated.id ? updated : $0 })
    }
  }

  public func remove(_ entry: AddressBookEntry) async {
    _ = await work("Could not remove \(entry.name).") { () async throws(TwakeContactsError) in
      try await self.repository.removeContact(entry)
      self.entries.removeAll { $0.id == entry.id }
    }
  }

  public func invite(_ address: ContactAddress) async -> Bool {
    guard features.invitations, invited[address] == nil else { return false }
    return await work("Could not send the invitation to \(address.address).") {
      () async throws(TwakeContactsError) in
      self.invited[address] = try await self.repository.sendInvitation(to: address)
    }
  }

  public func makeLink(for address: ContactAddress? = nil) async {
    guard features.invitations else { return }
    _ = await work("Could not create an invitation link.") { () async throws(TwakeContactsError) in
      self.link = try await self.repository.invitationLink(for: address)
    }
  }

  public func loadInvitations() async {
    guard features.invitations else { return }
    _ = await work("Could not load your invitations.") { () async throws(TwakeContactsError) in
      self.invitations = try await self.repository.invitations()
        .sorted { ($0.expiration ?? .distantPast) > ($1.expiration ?? .distantPast) }
    }
  }

  public func refresh(_ invitation: TwakeInvitation) async {
    _ = await work("Could not check this invitation.") { () async throws(TwakeContactsError) in
      let fresh = try await self.repository.invitation(id: invitation.id)
      self.invitations = self.invitations?.map { $0.id == fresh.id ? fresh : $0 }
    }
  }

  public func clearError() {
    errorMessage = nil
  }

  private func work(
    _ failure: String, _ body: @MainActor () async throws(TwakeContactsError) -> Void
  ) async -> Bool {
    guard !isWorking else { return false }
    isWorking = true
    errorMessage = nil
    defer { isWorking = false }
    do {
      try await body()
      return true
    } catch .tooManyRequests {
      errorMessage = "Too many invitations sent. Please try again later."
    } catch {
      errorMessage = failure
    }
    return false
  }

  private static func sorted(_ entries: [AddressBookEntry]) -> [AddressBookEntry] {
    entries.filter(\.active).sorted {
      $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
    }
  }
}
