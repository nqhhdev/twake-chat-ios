import Foundation
import Testing

@testable import MatrixData

/// A `preview_url` answer becomes a card; one with nothing to show does not.
struct LinkPreviewProxyTests {
  private let url = URL(string: "https://twake.app")!

  @Test func theOpenGraphFieldsAreRead() throws {
    let json = """
      {"og:title":"Twake","og:description":" Open source workplace ","og:site_name":"Linagora",
       "og:image:width":1200,"og:image:height":630}
      """
    let preview = try #require(LinkPreviewProxy.preview(of: url, from: Data(json.utf8)))
    #expect(preview.title == "Twake")
    #expect(preview.description == "Open source workplace")
    #expect(preview.siteName == "Linagora")
    #expect(preview.url == url)
  }

  @Test func anAnswerWithNothingToShowIsNoPreview() {
    #expect(LinkPreviewProxy.preview(of: url, from: Data(#"{"og:title":"  "}"#.utf8)) == nil)
    #expect(LinkPreviewProxy.preview(of: url, from: Data("nope".utf8)) == nil)
  }
}
