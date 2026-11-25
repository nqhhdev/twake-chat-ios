import AppShared
import Domain
import Foundation
import Testing
import UserNotifications

@testable import TwakeChat

@MainActor
struct NotificationActionTests {
  private actor RecordingActions: NotificationActionRepository {
    struct Reply: Equatable {
      let text: String
      let roomId: String
      let threadId: String?
      let eventId: String
    }

    private(set) var replies: [Reply] = []
    private(set) var markedRead: [String] = []
    private let fails: Bool

    init(fails: Bool = false) { self.fails = fails }

    func reply(text: String, roomId: String, threadId: String?, eventId: String)
      async throws(NotificationActionError)
    {
      if fails { throw .requestFailed }
      replies.append(Reply(text: text, roomId: roomId, threadId: threadId, eventId: eventId))
    }

    func markAsRead(roomId: String) async throws(NotificationActionError) {
      if fails { throw .requestFailed }
      markedRead.append(roomId)
    }
  }

  private let userInfo: [AnyHashable: Any] = [
    "room_id": "!r:b", "event_id": "$e", "thread_id": "$t", "unread_count": 2,
  ]

  @Test func aTapOpensTheRoomAndThread() throws {
    let action = try #require(
      NotificationAction(
        actionIdentifier: UNNotificationDefaultActionIdentifier, userText: nil,
        userInfo: userInfo, title: "Team"))
    #expect(action.kind == .open)
    #expect(action.roomId == "!r:b")
    #expect(action.eventId == "$e")
    #expect(action.threadId == "$t")
    #expect(action.title == "Team")
  }

  @Test func theReplyTextIsTrimmed() throws {
    let action = try #require(
      NotificationAction(
        actionIdentifier: PushPayload.replyAction, userText: "  Hi \n", userInfo: userInfo,
        title: ""))
    #expect(action.kind == .reply("Hi"))
  }

  @Test func aBlankReplyDoesNothing() {
    #expect(
      NotificationAction(
        actionIdentifier: PushPayload.replyAction, userText: "  ", userInfo: userInfo, title: "")
        == nil)
    #expect(
      NotificationAction(
        actionIdentifier: PushPayload.replyAction, userText: nil, userInfo: userInfo, title: "")
        == nil)
  }

  @Test func markAsReadIsRecognised() throws {
    let action = try #require(
      NotificationAction(
        actionIdentifier: PushPayload.markAsReadAction, userText: nil, userInfo: userInfo,
        title: ""))
    #expect(action.kind == .markAsRead)
  }

  @Test func dismissingOrANotificationWithoutRoomDoesNothing() {
    #expect(
      NotificationAction(
        actionIdentifier: UNNotificationDismissActionIdentifier, userText: nil,
        userInfo: userInfo, title: "") == nil)
    #expect(
      NotificationAction(
        actionIdentifier: UNNotificationDefaultActionIdentifier, userText: nil,
        userInfo: ["event_id": "$e"], title: "") == nil)
  }

  @Test func theMessageCategoryOffersReplyAndMarkAsRead() throws {
    let category = try #require(NotificationAction.categories.first)
    #expect(NotificationAction.categories.count == 1)
    #expect(category.identifier == PushPayload.messageCategory)
    #expect(
      category.actions.map(\.identifier) == [PushPayload.replyAction, PushPayload.markAsReadAction])
    #expect(category.actions.first is UNTextInputNotificationAction)
    #expect(category.actions.allSatisfy { !$0.options.contains(.foreground) })
  }

  @Test func aReplyIsSentThroughTheRepositoryOnceTheSessionStarted() async throws {
    let actions = RecordingActions()
    var started = 0
    var failures: [NotificationAction] = []
    let center = PushCenter(repository: nil, actions: actions, replyFailed: { failures.append($0) })
    center.startSession = { started += 1 }
    let action = try #require(
      NotificationAction(
        actionIdentifier: PushPayload.replyAction, userText: "Hi", userInfo: userInfo,
        title: "Team"))
    await center.handle(action)
    #expect(started == 1)
    #expect(
      await actions.replies == [
        .init(text: "Hi", roomId: "!r:b", threadId: "$t", eventId: "$e")
      ])
    #expect(failures.isEmpty)
    #expect(center.pendingRoomId == nil)
  }

  @Test func aFailedReplyTellsTheUser() async throws {
    var failures: [NotificationAction] = []
    let center = PushCenter(
      repository: nil, actions: RecordingActions(fails: true), replyFailed: { failures.append($0) })
    let action = try #require(
      NotificationAction(
        actionIdentifier: PushPayload.replyAction, userText: "Hi", userInfo: userInfo,
        title: "Team"))
    await center.handle(action)
    #expect(failures == [action])
  }

  @Test func aReplyWithoutRepositoryTellsTheUser() async throws {
    var failures: [NotificationAction] = []
    let center = PushCenter(repository: nil, replyFailed: { failures.append($0) })
    let action = try #require(
      NotificationAction(
        actionIdentifier: PushPayload.replyAction, userText: "Hi", userInfo: userInfo, title: ""))
    await center.handle(action)
    #expect(failures.count == 1)
  }

  @Test func markAsReadReachesTheRepository() async throws {
    let actions = RecordingActions()
    let center = PushCenter(repository: nil, actions: actions)
    let action = try #require(
      NotificationAction(
        actionIdentifier: PushPayload.markAsReadAction, userText: nil, userInfo: userInfo,
        title: ""))
    await center.handle(action)
    #expect(await actions.markedRead == ["!r:b"])
  }

  @Test func aTapSetsTheRoomAndThreadToOpen() async throws {
    let actions = RecordingActions()
    let center = PushCenter(repository: nil, actions: actions)
    let action = try #require(
      NotificationAction(
        actionIdentifier: UNNotificationDefaultActionIdentifier, userText: nil,
        userInfo: userInfo, title: "Team"))
    await center.handle(action)
    #expect(center.pendingRoomId == "!r:b")
    #expect(center.pendingThreadId == "$t")
    #expect(center.pendingRoomName == "Team")
    #expect(await actions.replies.isEmpty)
  }

  @Test func theFailureNoticeOpensTheSameChat() throws {
    let action = try #require(
      NotificationAction(
        actionIdentifier: PushPayload.replyAction, userText: "Hi", userInfo: userInfo,
        title: "Team"))
    let content = NotificationAction.replyFailureContent(for: action)
    #expect(content.title == "Team")
    #expect(content.threadIdentifier == "!r:b")
    #expect(PushPayload.roomId(in: content.userInfo) == "!r:b")
    #expect(PushPayload.threadId(in: content.userInfo) == "$t")
    #expect(content.categoryIdentifier.isEmpty)
  }
}
