import Domain
import Foundation
import Testing

@testable import Room

/// The Meet calls of a room (#92), on a fake repository.
@MainActor
struct MeetCallViewModelTests {
  actor FakeMeetCalls: MeetCallRepository {
    var base: URL?
    var result: Result<URL, MeetCallError>
    private(set) var started: [(roomId: String, base: URL, text: String)] = []

    init(base: URL?, result: Result<URL, MeetCallError>) {
      self.base = base
      self.result = result
    }

    func meetBaseURL() async -> URL? { base }

    func startCall(inRoom roomId: String, base: URL, text: String) async throws(MeetCallError)
      -> URL
    {
      started.append((roomId, base, text))
      return try result.get()
    }
  }

  private let base = URL(string: "https://meet.example.org")!
  private let link = URL(string: "https://meet.example.org/abc-defg-hij")!

  @Test func startingACallPostsItInTheRoomAndGivesItsLink() async {
    let repository = FakeMeetCalls(base: base, result: .success(link))
    let calls = MeetCallViewModel(roomId: "!room:example.org", repository: repository)
    await calls.load()
    #expect(await calls.start() == link)
    let started = await repository.started
    #expect(started.count == 1)
    #expect(started.first?.roomId == "!room:example.org")
    #expect(started.first?.base == base)
    #expect(started.first?.text == "Has started a video call")
    #expect(calls.errorMessage == nil)
    #expect(!calls.isStarting)
  }

  @Test func noCallStartsWithoutAMeetServer() async {
    let repository = FakeMeetCalls(base: nil, result: .success(link))
    let calls = MeetCallViewModel(roomId: "!room:example.org", repository: repository)
    await calls.load()
    #expect(calls.baseURL == nil)
    #expect(await calls.start() == nil)
    #expect(await repository.started.isEmpty)
  }

  @Test func aFailedStartSaysSo() async {
    let calls = MeetCallViewModel(
      roomId: "!room:example.org", repository: FakeMeetCalls(base: base, result: .failure(.failed)))
    await calls.load()
    #expect(await calls.start() == nil)
    #expect(calls.errorMessage == "Failed to start the call")
  }

  @Test func aRoomLeftMeanwhileStartsNothingQuietly() async {
    let calls = MeetCallViewModel(
      roomId: "!room:example.org",
      repository: FakeMeetCalls(base: base, result: .failure(.notJoined)))
    await calls.load()
    #expect(await calls.start() == nil)
    #expect(calls.errorMessage == nil)
  }

  @Test func onlyACallOnTheAccountsMeetServerIsACard() async {
    let calls = MeetCallViewModel(
      roomId: "!room:example.org", repository: FakeMeetCalls(base: base, result: .success(link)))
    #expect(
      calls.link(of: .link(link.absoluteString)) == nil, "no card before the Meet server is known")
    await calls.load()
    #expect(calls.link(of: .link(link.absoluteString)) == link)
    #expect(calls.link(of: .link("https://meet.evil.org/abc-defg-hij")) == nil)
    #expect(calls.link(of: .threadRoot) == nil)
    #expect(calls.link(of: nil) == nil)
  }
}
