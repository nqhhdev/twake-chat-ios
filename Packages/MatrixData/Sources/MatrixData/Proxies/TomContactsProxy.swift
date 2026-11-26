import Domain
import Foundation

public actor TomContactsProxy: TwakeContactsRepository {
  private let clientProxy: @Sendable () async -> ClientProxy?
  private let capabilities: any ServerCapabilitiesRepository
  private let transport: TomContactsAPI.Transport

  public init(
    authentication: MatrixAuthenticationRepository,
    capabilities: any ServerCapabilitiesRepository
  ) {
    clientProxy = { await authentication.clientProxy }
    self.capabilities = capabilities
    transport = { request in
      guard let (data, response) = try? await URLSession.shared.data(for: request),
        let http = response as? HTTPURLResponse
      else { return nil }
      return (http.statusCode, data)
    }
  }

  public func features() async -> TwakeContactsFeatures {
    let current = await capabilities.current()
    guard current.tom != nil else { return .none }
    return TwakeContactsFeatures(
      addressBook: true, invitations: current.twakeChat.invitationsEnabled)
  }

  public func addressBook() async throws(TwakeContactsError) -> [AddressBookEntry] {
    try await api().addressBook()
  }

  public func addContact(userId: String, displayName: String) async throws(TwakeContactsError)
    -> [AddressBookEntry]
  {
    let userId = userId.trimmingCharacters(in: .whitespacesAndNewlines)
    let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard AddressBookEntry.isUserId(userId), !name.isEmpty else { throw .invalid }
    return try await api().add(userId: userId, displayName: name)
  }

  public func updateContact(_ entry: AddressBookEntry, displayName: String)
    async throws(TwakeContactsError) -> AddressBookEntry
  {
    let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty else { throw .invalid }
    return try await api().update(entry, displayName: name)
  }

  public func removeContact(_ entry: AddressBookEntry) async throws(TwakeContactsError) {
    try await api().remove(entry)
  }

  public func sendInvitation(to address: ContactAddress) async throws(TwakeContactsError)
    -> String
  {
    try await invitationsAPI().invite(address)
  }

  public func invitationLink(for address: ContactAddress?) async throws(TwakeContactsError)
    -> InvitationLink
  {
    try await invitationsAPI().link(for: address)
  }

  public func invitations() async throws(TwakeContactsError) -> [TwakeInvitation] {
    try await invitationsAPI().invitations()
  }

  public func invitation(id: String) async throws(TwakeContactsError) -> TwakeInvitation {
    try await invitationsAPI().invitation(id: id)
  }

  private func invitationsAPI() async throws(TwakeContactsError) -> TomContactsAPI {
    let current = await capabilities.current()
    guard current.tom != nil, current.twakeChat.invitationsEnabled else { throw .unavailable }
    return try await api()
  }

  private func api() async throws(TwakeContactsError) -> TomContactsAPI {
    guard let client = await clientProxy(), let token = try? client.client.session().accessToken
    else { throw .notSignedIn }
    guard let tom = await capabilities.current().tom else { throw .unavailable }
    return TomContactsAPI(baseURL: tom.baseURL, accessToken: token, transport: transport)
  }
}
