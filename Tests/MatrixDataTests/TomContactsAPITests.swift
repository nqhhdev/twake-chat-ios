import Domain
import Foundation
import Testing

@testable import MatrixData

struct TomContactsAPITests {
  private let base = URL(string: "https://tom.example.org")!

  private func api(_ recorder: RecordingTransport) -> TomContactsAPI {
    TomContactsAPI(baseURL: base, accessToken: "mx-token", transport: recorder.transport)
  }

  @Test func theAddressBookIsReadWithTheMatrixToken() async throws {
    let recorder = RecordingTransport([
      (
        200,
        #"{"id":"ab","owner":"@me:example.org","contacts":[{"id":"1","mxid":"@bob:example.org","display_name":"Bob","active":true,"addressbook_id":"ab"},{"id":"2","mxid":"@x:example.org","display_name":"X","active":false}]}"#
      )
    ])
    let entries = try await api(recorder).addressBook()
    #expect(
      entries == [
        AddressBookEntry(id: "1", userId: "@bob:example.org", displayName: "Bob"),
        AddressBookEntry(id: "2", userId: "@x:example.org", displayName: "X", active: false),
      ])
    let request = try #require(recorder.requests.first)
    #expect(request.httpMethod == "GET")
    #expect(request.url?.absoluteString == "https://tom.example.org/_twake/addressbook")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer mx-token")
  }

  @Test func addingPostsTheContactsAsFlutterDoes() async throws {
    let recorder = RecordingTransport([
      (200, #"{"contacts":[{"id":"9","mxid":"@carol:example.org","display_name":"Carol"}]}"#)
    ])
    let entries = try await api(recorder).add(userId: "@carol:example.org", displayName: "Carol")
    #expect(entries.map(\.id) == ["9"])
    #expect(recorder.requests.first?.httpMethod == "POST")
    let contacts = recorder.body(0)?["contacts"] as? [[String: String]]
    #expect(contacts == [["mxid": "@carol:example.org", "display_name": "Carol"]])
  }

  @Test func editingAndRemovingUseTheContactId() async throws {
    let recorder = RecordingTransport([
      (200, #"{"id":"9","mxid":"@carol:example.org","display_name":"Caro","active":true}"#),
      (200, #"{"message":"Contact deleted"}"#),
    ])
    let carol = AddressBookEntry(id: "9", userId: "@carol:example.org", displayName: "Carol")
    let updated = try await api(recorder).update(carol, displayName: "Caro")
    #expect(updated.displayName == "Caro")
    try await api(recorder).remove(carol)
    #expect(recorder.requests.map(\.httpMethod) == ["PUT", "DELETE"])
    #expect(
      recorder.requests.map(\.url?.absoluteString) == [
        "https://tom.example.org/_twake/addressbook/9",
        "https://tom.example.org/_twake/addressbook/9",
      ])
    #expect(recorder.body(0)?["mxid"] as? String == "@carol:example.org")
    #expect(recorder.body(0)?["display_name"] as? String == "Caro")
    #expect(recorder.body(0)?["active"] as? Bool == true)
  }

  @Test func anInvitationSendsTheContactAndItsMedium() async throws {
    let recorder = RecordingTransport([
      (200, #"{"message":"Invitation sent","id":"inv1"}"#),
      (200, #"{"message":"Invitation sent","id":"inv2"}"#),
    ])
    let id = try await api(recorder).invite(ContactAddress.email("Carol@Example.org")!)
    #expect(id == "inv1")
    _ = try await api(recorder).invite(ContactAddress.phone("+33 6 12 34 56 78", regionCode: nil)!)
    #expect(recorder.requests.first?.url?.path() == "/_twake/v1/invite")
    #expect(
      recorder.body(0) as? [String: String] == ["contact": "carol@example.org", "medium": "email"])
    #expect(
      recorder.body(1) as? [String: String] == ["contact": "+33612345678", "medium": "phone"])
  }

  @Test func aLinkWithoutAContactSendsAnEmptyBody() async throws {
    let recorder = RecordingTransport([
      (200, #"{"link":"https://chat.example.org/?invitation_token=t1","id":"t1"}"#)
    ])
    let link = try await api(recorder).link(for: nil)
    #expect(
      link
        == InvitationLink(
          id: "t1", url: URL(string: "https://chat.example.org/?invitation_token=t1")!))
    #expect(recorder.requests.first?.url?.path() == "/_twake/v1/invite/generate")
    #expect(recorder.body(0)?.isEmpty == true)
  }

  @Test func invitationsAndTheirStatusAreRead() async throws {
    let recorder = RecordingTransport([
      (
        200,
        #"{"invitations":[{"id":"a","sender":"@me:example.org","recipient":"a@b.org","medium":"email","expiration":1764000000000,"accessed":true,"matrix_id":"@a:example.org"}]}"#
      ),
      (
        200,
        #"{"invitation":{"id":"b","recepient":"+33612345678","medium":"phone","expiration":1764000000000,"accessed":false}}"#
      ),
    ])
    let list = try await api(recorder).invitations()
    #expect(list.first?.recipient == "a@b.org")
    #expect(list.first?.kind == .email)
    #expect(list.first?.expiration == Date(timeIntervalSince1970: 1_764_000_000))
    #expect(list.first?.status() == .joined(userId: "@a:example.org"))
    let status = try await api(recorder).invitation(id: "b")
    #expect(status.recipient == "+33612345678")
    #expect(status.kind == .phone)
    #expect(!status.accessed)
    #expect(
      recorder.requests.map { $0.url?.path() } == [
        "/_twake/v1/invite/list", "/_twake/v1/invite/b/status",
      ])
  }

  @Test func errorsAreToldApart() async {
    let recorder = RecordingTransport([
      (400, #"{"message":"Invitations are not enabled"}"#), (401, "{}"), (429, "{}"), (500, "{}"),
    ])
    let api = api(recorder)
    let address = ContactAddress.email("a@b.org")!
    await #expect(throws: TwakeContactsError.invalid) { try await api.invite(address) }
    await #expect(throws: TwakeContactsError.notSignedIn) { try await api.invite(address) }
    await #expect(throws: TwakeContactsError.tooManyRequests) { try await api.invite(address) }
    await #expect(throws: TwakeContactsError.requestFailed) { try await api.invite(address) }
  }
}
