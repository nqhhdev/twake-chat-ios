import Foundation
import Testing

@testable import Domain

struct DrivePickPlanTests {
  private func document(
    _ name: String, mimeType: String? = "application/pdf", sharing: String? = nil,
    download: String? = nil
  ) -> DriveDocument {
    DriveDocument(
      id: name, name: name, size: 10, mimeType: mimeType,
      sharingLink: sharing.flatMap(URL.init(string:)),
      downloadLink: download.flatMap(URL.init(string:)))
  }

  @Test func sharingLinksMeanTheUserChoseLinks() {
    let plan = DrivePickPlan.plan([
      document("a.pdf", sharing: "https://d.example.org/s/a", download: "https://d.example.org/a"),
      document("b.pdf", download: "https://d.example.org/b"),
    ])
    #expect(plan == .links(["[a.pdf](https://d.example.org/s/a)"]))
  }

  @Test func eachLinkIsAMarkdownLineWithoutBracketsOrBreaksInItsLabel() {
    let plan = DrivePickPlan.plan([
      document("[draft]\\ one\n  two", sharing: "https://d.example.org/s/(x)"),
      document("c.pdf", sharing: "https://d.example.org/s/c"),
    ])
    #expect(
      plan
        == .links([
          "[draft one two](https://d.example.org/s/%28x%29)\n[c.pdf](https://d.example.org/s/c)"
        ]))
  }

  @Test func plainHttpLinksAreNotSent() {
    #expect(DrivePickPlan.plan([document("a", sharing: "http://d.example.org/s/a")]) == .nothingToSend)
    #expect(DrivePickPlan.plan([document("a", download: "http://d.example.org/a")]) == .nothingToSend)
  }

  @Test func longPicksAreSplitBetweenLinks() {
    let lines = DrivePickPlan.messages(of: ["aaaa", "bbbb", "cc"], maxLength: 9)
    #expect(lines == ["aaaa\nbbbb", "cc"])
    #expect(DrivePickPlan.messages(of: ["0123456789"], maxLength: 4) == ["0123456789"])
  }

  @Test func aLabelIsCutWithoutSplittingAPair() {
    #expect(DrivePickPlan.cut("a😀b", to: 2) == "a")
    #expect(DrivePickPlan.cut("a😀b", to: 3) == "a😀")
  }

  @Test func aLinkTooLongForOneMessageIsLeftOut() {
    let long = "https://d.example.org/" + String(repeating: "x", count: 4000)
    #expect(DrivePickPlan.plan([document("a", sharing: long)]) == .nothingToSend)
  }

  @Test func shortcutsAreNeverAttached() {
    let file = document("a.pdf", download: "https://d.example.org/a")
    let plan = DrivePickPlan.plan([
      file, document("site.URL", download: "https://d.example.org/u"),
      document("x", mimeType: "application/internet-shortcut", download: "https://d.example.org/x"),
    ])
    #expect(plan == .attach([file], skippedShortcuts: 2))
    #expect(
      DrivePickPlan.plan([document("site.url", download: "https://d.example.org/u")])
        == .shortcutsOnly)
  }

  @Test func theOriginDropsTheDefaultPort() {
    #expect(DrivePicker.origin(scheme: "HTTPS", host: "D.example.org", port: 443) == "https://d.example.org")
    #expect(DrivePicker.origin(scheme: "https", host: "d.example.org", port: 0) == "https://d.example.org")
    #expect(DrivePicker.origin(scheme: "https", host: "d.example.org", port: 8443) == "https://d.example.org:8443")
    #expect(DrivePicker.origin(scheme: "https", host: "", port: nil) == nil)
  }
}
