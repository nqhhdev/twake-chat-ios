import Domain
import Foundation
import Testing

/// The Matrix links the app opens itself, as the Flutter `UrlLauncher` reads them.
struct MatrixLinkTests {
  private func link(_ text: String) -> MatrixLink? {
    URL(string: text).flatMap(MatrixLink.init(url:))
  }

  @Test func aMatrixToRoomAliasWithServers() {
    #expect(
      link("https://matrix.to/#/%23team%3Aexample.org?via=example.org&via=other.org")
        == .room(idOrAlias: "#team:example.org", eventId: nil, via: ["example.org", "other.org"]))
  }

  @Test func aMatrixToMessage() {
    #expect(
      link("https://matrix.to/#/!abc%3Aexample.org/%24event1?via=example.org")
        == .room(idOrAlias: "!abc:example.org", eventId: "$event1", via: ["example.org"]))
  }

  @Test func aMatrixToPerson() {
    #expect(link("https://matrix.to/#/@alice:example.org") == .user(id: "@alice:example.org"))
  }

  @Test func theAppSchemeIsReadAsMatrixTo() {
    #expect(
      link("twake.chat://chat/%23team:example.org")
        == .room(idOrAlias: "#team:example.org", eventId: nil, via: []))
  }

  @Test func theMatrixScheme() {
    #expect(link("matrix:u/alice:example.org") == .user(id: "@alice:example.org"))
    #expect(
      link("matrix:r/team:example.org")
        == .room(idOrAlias: "#team:example.org", eventId: nil, via: []))
    #expect(
      link("matrix:roomid/abc:example.org/e/event1?via=example.org")
        == .room(idOrAlias: "!abc:example.org", eventId: "$event1", via: ["example.org"]))
  }

  @Test func otherLinksAreNotMatrixLinks() {
    #expect(link("https://twake.app") == nil)
    #expect(link("https://matrix.to/") == nil)
    #expect(link("https://matrix.to/#/hello") == nil)
    #expect(link("matrix:x/y") == nil)
  }
}
