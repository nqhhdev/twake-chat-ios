import Domain
import Foundation
import Testing

/// Meet call links as the Twake clients post them (#92).
struct MeetLinkTests {
  private let base = URL(string: "https://meet.example.org")!

  @Test func aBaseIsHttpsWithoutTrailingSlashQueryOrFragment() {
    #expect(
      MeetLink.base(URL(string: "https://meet.example.org/")!)?.absoluteString
        == "https://meet.example.org")
    #expect(
      MeetLink.base(URL(string: "https://example.org/meet/")!)?.absoluteString
        == "https://example.org/meet")
    #expect(MeetLink.base(URL(string: "http://meet.example.org")!) == nil)
    #expect(MeetLink.base(URL(string: "https://meet.example.org/?room=1")!) == nil)
    #expect(MeetLink.base(URL(string: "https://meet.example.org/#top")!) == nil)
  }

  @Test func aSlugIsThreeFourAndThreeLowercaseLetters() {
    #expect(MeetLink.isSlug("abc-defg-hij"))
    #expect(!MeetLink.isSlug("abc-def-hij"))
    #expect(!MeetLink.isSlug("ABC-defg-hij"))
    #expect(!MeetLink.isSlug("abc-defg-hi1"))
    #expect(!MeetLink.isSlug("abc-defg-hij-klm"))
    #expect(!MeetLink.isSlug("àbc-defg-hij"))
  }

  @Test func aRandomSlugIsASlug() {
    for _ in 0..<50 { #expect(MeetLink.isSlug(MeetLink.randomSlug())) }
    #expect(MeetLink.randomSlug() != MeetLink.randomSlug())
  }

  @Test func aLinkIsTheSlugUnderTheBase() {
    #expect(
      MeetLink.link(slug: "abc-defg-hij", base: base).absoluteString
        == "https://meet.example.org/abc-defg-hij")
    let nested = URL(string: "https://example.org/meet")!
    #expect(
      MeetLink.link(slug: "abc-defg-hij", base: nested).absoluteString
        == "https://example.org/meet/abc-defg-hij")
  }

  @Test func aCallLinkIsOneSlugOnTheSameMeetServer() {
    #expect(MeetLink.callLink("https://meet.example.org/abc-defg-hij", base: base) != nil)
    #expect(MeetLink.callLink("https://MEET.example.org/abc-defg-hij", base: base) != nil)
    #expect(MeetLink.callLink("https://meet.evil.org/abc-defg-hij", base: base) == nil)
    #expect(MeetLink.callLink("http://meet.example.org/abc-defg-hij", base: base) == nil)
    #expect(MeetLink.callLink("https://meet.example.org:8443/abc-defg-hij", base: base) == nil)
    #expect(MeetLink.callLink("https://meet.example.org/abc-defg-hij?x=1", base: base) == nil)
    #expect(MeetLink.callLink("https://meet.example.org/a/abc-defg-hij", base: base) == nil)
    #expect(MeetLink.callLink("https://meet.example.org/not-a-slug", base: base) == nil)
    #expect(MeetLink.callLink("not a link", base: base) == nil)
  }

  @Test func aSlugIsReadUnderABaseWithAPath() {
    let nested = URL(string: "https://example.org/meet")!
    #expect(
      MeetLink.slug(of: URL(string: "https://example.org/meet/abc-defg-hij")!, base: nested)
        == "abc-defg-hij")
    #expect(
      MeetLink.slug(of: URL(string: "https://example.org/abc-defg-hij")!, base: nested) == nil)
  }
}
