import Domain
import Foundation
import MatrixRustSDK

/// `PeopleRepository` on the SDK client (ADR 0006): the user directory, direct chats and new groups. Nothing here logs.
public actor PeopleProxy: PeopleRepository {
  /// How many people one search returns.
  static let searchLimit: UInt64 = 30

  private let clientProxy: @Sendable () async -> ClientProxy?
  private let lookup = TwakeContactLookup()
  /// The ToM server found for this account, looked up once.
  private var tom: (baseURL: URL, serverName: String)??

  public init(authentication: MatrixAuthenticationRepository) {
    clientProxy = { await authentication.clientProxy }
  }

  public func search(_ text: String) async throws(PeopleError) -> [Person] {
    let term = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !term.isEmpty else { return [] }
    let client = try await client()
    let ownUserId = try? client.userId
    var people: [Person] = []
    // Twake's address book first, as the Flutter app searches it; the Matrix user directory adds whoever it misses.
    if let tom = await tomServer(ownUserId), let token = try? client.client.session().accessToken,
      let matches = try? await lookup.search(
        term, limit: Int(Self.searchLimit), tom: tom.baseURL, serverName: tom.serverName,
        accessToken: token)
    {
      people = matches.map { Person(id: $0.userId, displayName: $0.displayName) }
    }
    if let directory = try? await client.client.searchUsers(
      searchTerm: term, limit: Self.searchLimit)
    {
      for profile in directory.results where !people.contains(where: { $0.id == profile.userId }) {
        people.append(Person(id: profile.userId, displayName: profile.displayName))
      }
    }
    people.removeAll { $0.id == ownUserId }
    // A full Matrix id that neither lists can still be invited.
    if term.hasPrefix("@"), term.contains(":"), !people.contains(where: { $0.id == term }) {
      people.insert(Person(id: term, displayName: nil), at: 0)
    }
    return people
  }

  private func tomServer(_ userId: String?) async -> (baseURL: URL, serverName: String)? {
    if let tom { return tom }
    guard let userId else { return nil }
    let found = await lookup.tomServer(forUserId: userId)
    tom = .some(found)
    return found
  }

  public func directChat(with userId: String) async throws(PeopleError) -> String {
    let client = try await client()
    if let existing = try? client.client.getDmRoom(userId: userId) { return existing.id() }
    do {
      return try await client.client.createRoom(
        request: CreateRoomParameters(
          name: nil, isEncrypted: true, isDirect: true, visibility: .private,
          preset: .trustedPrivateChat,
          invite: [userId]))
    } catch {
      throw .requestFailed
    }
  }

  public func createGroup(name: String, inviting userIds: [String]) async throws(PeopleError)
    -> String
  {
    let client = try await client()
    do {
      return try await client.client.createRoom(
        request: CreateRoomParameters(
          name: name.trimmingCharacters(in: .whitespacesAndNewlines), isEncrypted: true,
          isDirect: false,
          visibility: .private, preset: .privateChat, invite: userIds))
    } catch {
      throw .requestFailed
    }
  }

  private func client() async throws(PeopleError) -> ClientProxy {
    guard let client = await clientProxy() else { throw .notSignedIn }
    return client
  }
}
