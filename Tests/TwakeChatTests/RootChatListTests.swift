import Authentication
import AuthenticationTestSupport
import ChatList
import Domain
import Foundation
import Testing

@testable import TwakeChat

/// The root joins the two features: signed in, it gives the chat list, whose Log out runs the authentication logout and
/// returns to the sign-in form (TWAK-66).
@MainActor
struct RootChatListTests {
  /// A room list that never yields; the root only needs one to build the chat list.
  private struct SilentRoomList: RoomListRepository {
    func start() async throws(RoomListError) -> AsyncStream<[RoomSummary]> {
      AsyncStream { _ in }
    }
    func accept(roomId: String) async throws(RoomListError) {}
    func decline(roomId: String) async throws(RoomListError) {}
    func setUnread(_ unread: Bool, roomId: String) async throws(RoomListError) {}
    func setFavourite(_ favourite: Bool, roomId: String) async throws(RoomListError) {}
    func leave(roomId: String) async throws(RoomListError) {}
    func setMuted(_ muted: Bool, roomId: String) async throws(RoomListError) {}
    func stop() async {}
  }

  private let session = UserSession(
    userId: "@alice:example.org", deviceId: "DEVICE",
    homeserverURL: URL(string: "https://matrix.example.org")!, accessToken: "token",
    refreshToken: nil)

  private func signedInRoot(_ repository: FakeAuthenticationRepository) async throws -> (
    RootCoordinator, SignedInViewModel
  ) {
    repository.restoreResult = .success(session)
    let root = RootCoordinator(
      repository: repository, roomList: SilentRoomList(), defaultHomeserver: nil)
    await root.start()
    guard case .signedIn(let signedIn) = root.authentication?.screen else {
      Issue.record("expected the signed-in state")
      throw CancellationError()
    }
    return (root, signedIn)
  }

  @Test func signedInGivesOneChatListPerSignIn() async throws {
    let (root, signedIn) = try await signedInRoot(FakeAuthenticationRepository())
    let chatList = try #require(root.chatList(for: signedIn))
    #expect(root.chatList(for: signedIn) === chatList)
  }

  @Test func withoutARoomListThereIsNoChatList() async throws {
    let repository = FakeAuthenticationRepository()
    repository.restoreResult = .success(session)
    let root = RootCoordinator(repository: repository, defaultHomeserver: nil)
    await root.start()
    guard case .signedIn(let signedIn) = root.authentication?.screen else {
      Issue.record("expected the signed-in state")
      return
    }
    #expect(root.chatList(for: signedIn) == nil)
  }

  @Test func chatListLogOutReturnsToTheSignInForm() async throws {
    let repository = FakeAuthenticationRepository()
    let (root, signedIn) = try await signedInRoot(repository)
    let chatList = try #require(root.chatList(for: signedIn))
    await chatList.logOut()
    #expect(repository.logoutCallCount == 1)
    #expect(chatList.logOutErrorMessage == nil)
    guard isSignedOut(root) else {
      Issue.record("expected the sign-in form after logout")
      return
    }
  }

  @Test func aFailedChatListLogOutStaysSignedInWithAnError() async throws {
    let repository = FakeAuthenticationRepository()
    repository.logoutResult = .failure(.serverUnreachable)
    let (root, signedIn) = try await signedInRoot(repository)
    let chatList = try #require(root.chatList(for: signedIn))
    await chatList.logOut()
    #expect(chatList.logOutErrorMessage == "Could not log out. Please try again.")
    guard case .signedIn = root.authentication?.screen else {
      Issue.record("expected to stay signed in")
      return
    }
  }

  // MARK: Tester (TWAK-66): a second sign-in after logout.

  /// Log out, sign in again as someone else: the root gives a new chat list for the new signed-in state, not the
  /// previous user's one, and its Log out still reaches the authentication repository.
  @Test func signingInAgainAfterLogOutGivesANewChatList() async throws {
    let repository = FakeAuthenticationRepository()
    let (root, firstSignedIn) = try await signedInRoot(repository)
    let firstChatList = try #require(root.chatList(for: firstSignedIn))
    await firstChatList.logOut()
    guard let form = await passwordForm(of: root) else {
      Issue.record("expected the sign-in form after logout")
      return
    }

    let bob = UserSession(
      userId: "@bob:example.org", deviceId: "DEVICE2",
      homeserverURL: URL(string: "https://matrix.example.org")!, accessToken: "token2",
      refreshToken: nil)
    repository.loginResult = .success(bob)
    form.homeserver = "https://matrix.example.org"
    form.username = "bob"
    form.password = "password"
    await form.signIn()
    guard case .signedIn(let secondSignedIn) = root.authentication?.screen else {
      Issue.record("expected the signed-in state after the second sign-in")
      return
    }
    #expect(secondSignedIn.userId == bob.userId)

    let secondChatList = try #require(root.chatList(for: secondSignedIn))
    #expect(secondChatList !== firstChatList)
    await secondChatList.logOut()
    #expect(repository.logoutCallCount == 2)
  }
}
