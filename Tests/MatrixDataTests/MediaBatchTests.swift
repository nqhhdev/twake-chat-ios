import Testing

@testable import MatrixData

/// Twake web and Flutter tie the pictures of one send with `app.twake.chat.batch` in each event's content; the room
/// groups only pictures that share it.
struct MediaBatchTests {
  @Test func theBatchIdIsReadFromTheEventContent() {
    let json = #"{"content":{"msgtype":"m.image","app.twake.chat.batch":"42"}}"#
    #expect(MediaBatch.id(inOriginalJSON: json) == "42")
  }

  @Test func anEventWithoutAUsableBatchIdHasNone() {
    #expect(MediaBatch.id(inOriginalJSON: nil) == nil)
    #expect(MediaBatch.id(inOriginalJSON: #"{"content":{"msgtype":"m.image"}}"#) == nil)
    #expect(MediaBatch.id(inOriginalJSON: #"{"content":{"app.twake.chat.batch":""}}"#) == nil)
    #expect(MediaBatch.id(inOriginalJSON: #"{"content":{"app.twake.chat.batch":7}}"#) == nil)
    #expect(MediaBatch.id(inOriginalJSON: "not json") == nil)
  }

  /// A forwarded copy never keeps the id of the original send, or forwarding two pictures of one album into a room
  /// would merge them into one album there.
  @Test func aForwardedContentLosesTheBatchId() {
    var content: [String: Any] = ["msgtype": "m.image", MediaBatch.contentKey: "42"]
    MediaBatch.remove(from: &content)
    #expect(content[MediaBatch.contentKey] == nil)
    #expect(content["msgtype"] as? String == "m.image")
  }
}
