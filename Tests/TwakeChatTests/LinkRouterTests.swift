import Domain
import Foundation
import Testing

@testable import TwakeChat

/// Matrix links open in the app: a room the user is in, a preview to join, a person to message.
@MainActor
struct LinkRouterTests {
  private actor Rooms: RoomLinkRepository {
    var targets: [String: RoomLinkTarget] = [:]
    var joinFails = false
    private(set) var joined: [String] = []

    func set(_ target: RoomLinkTarget, for idOrAlias: String) { targets[idOrAlias] = target }
    func failJoins() { joinFails = true }

    func target(of idOrAlias: String, via: [String]) async throws(RoomLinkError) -> RoomLinkTarget {
      guard let target = targets[idOrAlias] else { throw .notFound }
      return target
    }

    func join(_ idOrAlias: String, via: [String]) async throws(RoomLinkError) -> String {
      if joinFails { throw .requestFailed }
      joined.append(idOrAlias)
      return "!joined:example.org"
    }
  }

  private let preview = RoomLinkPreview(
    idOrAlias: "#public:example.org", name: "Public", topic: nil, memberCount: 3, avatar: nil,
    isPublic: true)

  @Test func otherLinksStayWithTheSystem() {
    let router = LinkRouter(rooms: Rooms(), openDirectChat: nil)
    #expect(router.handle(URL(string: "https://twake.app")!) == false)
  }

  @Test func aRoomTheUserIsInOpensOnTheLinkedMessage() async {
    let rooms = Rooms()
    await rooms.set(.member(roomId: "!r:example.org"), for: "#team:example.org")
    let router = LinkRouter(rooms: rooms, openDirectChat: nil)
    #expect(router.handle(URL(string: "https://matrix.to/#/%23team:example.org/%24e1")!))
    while router.opening == nil { await Task.yield() }
    #expect(router.opening == .init(roomId: "!r:example.org", eventId: "$e1"))
  }

  @Test func anotherRoomShowsItsPreviewThenJoins() async {
    let rooms = Rooms()
    await rooms.set(.preview(preview), for: "#public:example.org")
    let router = LinkRouter(rooms: rooms, openDirectChat: nil)
    router.handle(URL(string: "https://matrix.to/#/%23public:example.org?via=example.org")!)
    while router.joining == nil { await Task.yield() }
    #expect(router.joining?.via == ["example.org"])
    await router.join()
    #expect(await rooms.joined == ["#public:example.org"])
    #expect(router.joining == nil)
    #expect(router.opening == .init(roomId: "!joined:example.org", eventId: nil))
  }

  @Test func aFailedJoinKeepsThePreviewAndSaysWhy() async {
    let rooms = Rooms()
    await rooms.set(.preview(preview), for: "#public:example.org")
    await rooms.failJoins()
    let router = LinkRouter(rooms: rooms, openDirectChat: nil)
    await router.follow("#public:example.org", eventId: nil, via: [])
    await router.join()
    #expect(router.joining != nil)
    #expect(router.errorMessage == "Could not join this chat. Please try again.")
  }

  @Test func aRoomThatCannotBeFoundSaysSo() async {
    let router = LinkRouter(rooms: Rooms(), openDirectChat: nil)
    await router.follow("#nowhere:example.org", eventId: nil, via: [])
    #expect(router.errorMessage == "This chat could not be found.")
  }

  @Test func aPersonOffersADirectChat() async {
    var opened: [String] = []
    let router = LinkRouter(
      rooms: Rooms(),
      openDirectChat: { userId in
        opened.append(userId)
        return true
      })
    router.handle(URL(string: "https://matrix.to/#/@alice:example.org")!)
    #expect(router.person == "@alice:example.org")
    await router.message("@alice:example.org")
    #expect(opened == ["@alice:example.org"])
    #expect(router.person == nil)
  }
}
