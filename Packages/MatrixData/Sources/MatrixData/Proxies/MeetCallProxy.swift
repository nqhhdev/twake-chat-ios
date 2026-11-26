import Domain
import Foundation
import MatrixRustSDK

/// `MeetCallRepository` on the SDK client (ADR 0006, #92). The well-known is read once per account. A call link is
/// made as the Flutter app makes it: a room from ToM when it makes one, otherwise a random slug; then it is posted in
/// the room as a text message with the link under `call_url`. Nothing here logs: the message is content.
public actor MeetCallProxy: MeetCallRepository {
  private let clientProxy: @Sendable () async -> ClientProxy?
  private let meet: TwakeMeet
  private let capabilities: any ServerCapabilitiesRepository

  public init(
    authentication: MatrixAuthenticationRepository,
    capabilities: any ServerCapabilitiesRepository
  ) {
    clientProxy = { await authentication.clientProxy }
    meet = TwakeMeet()
    self.capabilities = capabilities
  }

  public func meetBaseURL() async -> URL? {
    guard await clientProxy() != nil else { return nil }
    return Self.meetBase(of: await capabilities.current())
  }

  static func meetBase(of capabilities: ServerCapabilities) -> URL? {
    capabilities.callFoci.lazy.compactMap(MeetLink.base).first
  }

  public func startCall(inRoom roomId: String, base: URL, text: String) async throws(MeetCallError)
    -> URL
  {
    guard let client = await clientProxy(), let room = try? client.client.getRoom(roomId: roomId),
      room.membership() == .joined
    else { throw .notJoined }
    let slug = try await slug(on: base, client: client)
    let link = MeetLink.link(slug: slug, base: base)
    guard
      let data = try? JSONSerialization.data(
        withJSONObject: CallEvents.messageContent(text: text, link: link)),
      let content = String(data: data, encoding: .utf8)
    else { throw .failed }
    do {
      try await room.sendRaw(eventType: "m.room.message", content: content)
    } catch {
      throw .failed
    }
    return link
  }

  /// The slug of the new call: ToM's room when it makes one, which must be one slug on `base`, since other clients
  /// show only those links as calls; a random slug when ToM makes none.
  private func slug(on base: URL, client: ClientProxy) async throws(MeetCallError) -> String {
    guard let tom = await capabilities.current().tom?.baseURL,
      let token = try? client.client.session().accessToken
    else { return MeetLink.randomSlug() }
    switch await meet.createRoom(tom: tom, accessToken: token) {
    case .created(let url):
      guard let slug = MeetLink.slug(of: url, base: base) else { throw .failed }
      return slug
    case .unavailable:
      return MeetLink.randomSlug()
    case .failed:
      throw .failed
    }
  }
}
