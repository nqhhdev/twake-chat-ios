import Domain
import Foundation

struct TomContactsAPI: Sendable {
  typealias Transport = @Sendable (URLRequest) async -> (Int, Data)?

  let baseURL: URL
  let accessToken: String
  let transport: Transport

  func addressBook() async throws(TwakeContactsError) -> [AddressBookEntry] {
    Self.entries(from: try await send(request("_twake/addressbook", method: "GET")))
  }

  func add(userId: String, displayName: String) async throws(TwakeContactsError)
    -> [AddressBookEntry]
  {
    let object = try await send(
      request(
        "_twake/addressbook", method: "POST",
        json: ["contacts": [["mxid": userId, "display_name": displayName]]]))
    return Self.entries(from: object)
  }

  func update(_ entry: AddressBookEntry, displayName: String) async throws(TwakeContactsError)
    -> AddressBookEntry
  {
    let object = try await send(
      request(
        "_twake/addressbook/\(entry.id)", method: "PUT",
        json: ["mxid": entry.userId, "display_name": displayName, "active": entry.active]))
    guard let updated = Self.entry(from: object) else { throw .requestFailed }
    return updated
  }

  func remove(_ entry: AddressBookEntry) async throws(TwakeContactsError) {
    _ = try await send(request("_twake/addressbook/\(entry.id)", method: "DELETE"))
  }

  func invite(_ address: ContactAddress) async throws(TwakeContactsError) -> String {
    let object = try await send(
      request("_twake/v1/invite", method: "POST", json: Self.invitationBody(address)))
    guard let id = object["id"] as? String else { throw .requestFailed }
    return id
  }

  func link(for address: ContactAddress?) async throws(TwakeContactsError) -> InvitationLink {
    let object = try await send(
      request(
        "_twake/v1/invite/generate", method: "POST",
        json: address.map(Self.invitationBody) ?? [:]))
    guard let id = object["id"] as? String, let link = object["link"] as? String,
      let url = URL(string: link)
    else { throw .requestFailed }
    return InvitationLink(id: id, url: url)
  }

  func invitations() async throws(TwakeContactsError) -> [TwakeInvitation] {
    let object = try await send(request("_twake/v1/invite/list", method: "GET"))
    let list = object["invitations"] as? [[String: Any]] ?? []
    return list.compactMap { Self.invitation(from: $0) }
  }

  func invitation(id: String) async throws(TwakeContactsError) -> TwakeInvitation {
    let object = try await send(
      request("_twake/v1/invite/\(id)/status", method: "GET"))
    guard
      let invitation = (object["invitation"] as? [String: Any]).flatMap({
        Self.invitation(from: $0)
      })
    else { throw .requestFailed }
    return invitation
  }

  static func invitationBody(_ address: ContactAddress) -> [String: Any] {
    ["contact": address.address, "medium": address.kind == .email ? "email" : "phone"]
  }

  static func entries(from object: [String: Any]) -> [AddressBookEntry] {
    (object["contacts"] as? [[String: Any]] ?? []).compactMap { entry(from: $0) }
  }

  static func entry(from object: [String: Any]) -> AddressBookEntry? {
    guard let id = object["id"] as? String, let userId = object["mxid"] as? String else {
      return nil
    }
    return AddressBookEntry(
      id: id, userId: userId, displayName: object["display_name"] as? String ?? "",
      active: object["active"] as? Bool ?? true)
  }

  static func invitation(from object: [String: Any]) -> TwakeInvitation? {
    guard let id = object["id"] as? String else { return nil }
    let kind: LinkedAddress.Kind? =
      switch object["medium"] as? String {
      case "email": .email
      case "phone": .phone
      default: nil
      }
    let expiration = (object["expiration"] as? NSNumber).map {
      Date(timeIntervalSince1970: $0.doubleValue / 1000)
    }
    return TwakeInvitation(
      id: id, recipient: (object["recipient"] ?? object["recepient"]) as? String ?? "",
      kind: kind, expiration: expiration, accessed: object["accessed"] as? Bool ?? false,
      userId: object["matrix_id"] as? String)
  }

  static func error(status: Int) -> TwakeContactsError {
    switch status {
    case 400: .invalid
    case 401: .notSignedIn
    case 403, 404: .unavailable
    case 429: .tooManyRequests
    default: .requestFailed
    }
  }

  private func request(_ path: String, method: String, json: [String: Any]? = nil)
    -> URLRequest
  {
    var request = URLRequest(url: baseURL.appending(path: path, directoryHint: .notDirectory))
    request.httpMethod = method
    request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
    if let json {
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      request.httpBody = try? JSONSerialization.data(withJSONObject: json)
    }
    return request
  }

  private func send(_ request: URLRequest) async throws(TwakeContactsError) -> [String: Any] {
    guard let (status, data) = await transport(request) else { throw .requestFailed }
    guard status == 200 else { throw Self.error(status: status) }
    return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
  }
}
