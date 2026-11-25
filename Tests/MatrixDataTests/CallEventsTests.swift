import Domain
import Foundation
import Testing

@testable import MatrixData

/// Call messages and call events as the Flutter app and the web client write them (#92).
struct CallEventsTests {
  @Test func aMessageWithACallLinkIsACall() {
    let json = #"""
      {"type":"m.room.message","content":{"msgtype":"m.text","body":"Has started a video call https://meet.example.org/abc-defg-hij","call_url":"https://meet.example.org/abc-defg-hij"}}
      """#
    #expect(CallEvents.mark(inOriginalJSON: json) == .link("https://meet.example.org/abc-defg-hij"))
  }

  @Test func theWebsCallThreadRootIsACall() {
    let json = #"""
      {"type":"m.room.message","content":{"msgtype":"m.text","body":"Call started at 10:00","app.twake.chat.call_thread":{}}}
      """#
    #expect(CallEvents.mark(inOriginalJSON: json) == .threadRoot)
  }

  @Test func otherMessagesAreNoCall() {
    #expect(CallEvents.mark(inOriginalJSON: nil) == nil)
    #expect(
      CallEvents.mark(inOriginalJSON: #"{"content":{"msgtype":"m.text","body":"hello"}}"#) == nil)
    // The words in the text alone make no call.
    #expect(
      CallEvents.mark(inOriginalJSON: #"{"content":{"msgtype":"m.text","body":"call_url"}}"#) == nil
    )
    #expect(
      CallEvents.mark(inOriginalJSON: #"{"content":{"msgtype":"m.text","body":"x","call_url":""}}"#)
        == nil)
    #expect(CallEvents.mark(inOriginalJSON: "call_url not json") == nil)
  }

  @Test func callSignallingAndMatrixRTCEventsAreCallEvents() {
    for type in [
      "m.call.invite", "m.call.hangup", "org.matrix.call.sdp_stream_metadata_changed",
      "com.famedly.call.member",
      "org.matrix.msc3401.call.member", "org.matrix.msc4075.call.notify",
      "org.matrix.msc4075.rtc.notification",
    ] {
      #expect(CallEvents.isCallEvent(type), "\(type)")
    }
    #expect(!CallEvents.isCallEvent("m.room.message"))
    #expect(!CallEvents.isCallEvent("m.room.member"))
  }

  @Test func aCallMessageCarriesTheLinkInItsTextAndUnderCallURL() throws {
    let link = URL(string: "https://meet.example.org/abc-defg-hij")!
    let content = CallEvents.messageContent(text: "Has started a video call", link: link)
    #expect(content["msgtype"] as? String == "m.text")
    #expect(
      content["body"] as? String == "Has started a video call https://meet.example.org/abc-defg-hij"
    )
    #expect(content["call_url"] as? String == "https://meet.example.org/abc-defg-hij")
    // What is sent reads back as a call.
    let data = try JSONSerialization.data(withJSONObject: [
      "type": "m.room.message", "content": content,
    ])
    #expect(
      CallEvents.mark(inOriginalJSON: String(decoding: data, as: UTF8.self))
        == .link(link.absoluteString))
  }
}
