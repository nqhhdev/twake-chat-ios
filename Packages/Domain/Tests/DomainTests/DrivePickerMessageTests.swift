import Domain
import Foundation
import Testing

struct DrivePickerMessageTests {
  @Test func messagesOfOtherIntentsAreUnknown() {
    #expect(DrivePickerMessage.parse(#"{"type":"intent-i1:ready"}"#, intentId: "i1") == .ready)
    #expect(
      DrivePickerMessage.parse(#"{"type":"intent-i1:readyToUse"}"#, intentId: "i1") == .readyToUse)
    #expect(DrivePickerMessage.parse(#"{"type":"intent-i1:cancel"}"#, intentId: "i1") == .cancel)
    #expect(DrivePickerMessage.parse(#"{"type":"intent-i1:error"}"#, intentId: "i1") == .error)
    #expect(DrivePickerMessage.parse(#"{"type":"intent-i2:ready"}"#, intentId: "i1") == .unknown)
    #expect(DrivePickerMessage.parse("not json", intentId: "i1") == nil)
  }

  @Test func doneKeepsOnlySafeDocuments() {
    let raw = """
      {"type":"intent-i1:done","document":[
        {"id":"a","name":"a.pdf","size":10,"mimeType":"application/pdf","downloadLink":"https://d.example.org/a","sharingLink":"https://d.example.org/s/a"},
        {"id":"b","name":"b.txt","size":-1},
        {"id":"c","name":"c.txt","size":3,"downloadLink":"javascript:alert(1)"},
        {"name":"no id","size":1}
      ]}
      """
    guard case .done(let documents) = DrivePickerMessage.parse(raw, intentId: "i1") else {
      Issue.record("Not a done message")
      return
    }
    #expect(documents.map(\.id) == ["a"])
    #expect(documents.first?.downloadLink?.absoluteString == "https://d.example.org/a")
    #expect(documents.first?.mimeType == "application/pdf")
  }

  @Test func theOriginIsTheSchemeHostAndPort() {
    let picker = DrivePicker(
      intentId: "i", url: URL(string: "https://d.example.org:8443/pick?x=1")!, client: "c",
      acknowledgement: "{}")
    #expect(picker.origin == "https://d.example.org:8443")
  }
}
