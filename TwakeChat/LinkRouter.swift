import DesignSystem
import Domain
import Observation
import SwiftUI

/// Opens Matrix links in the app (Flutter `UrlLauncher.openMatrixToUrl`): a link tapped in a message, or one the system
/// hands the app (`twake.chat://`, `matrix:`). A room the user is in opens, on the linked message when there is one;
/// another room shows its preview to join; a person offers a direct chat. Other links are not the router's.
@MainActor @Observable
final class LinkRouter {
  /// A room to open and maybe a message in it; the shell takes it.
  struct Opening: Equatable {
    let roomId: String
    let eventId: String?
  }

  /// A room the user is not in, shown before joining.
  struct Joining: Identifiable, Equatable {
    let preview: RoomLinkPreview
    let via: [String]
    let eventId: String?
    var id: String { preview.idOrAlias }
  }

  var opening: Opening?
  var joining: Joining?
  /// A person's Matrix id, to offer a direct chat with.
  var person: String?
  private(set) var isJoining = false
  private(set) var errorMessage: String?

  @ObservationIgnored private let rooms: (any RoomLinkRepository)?
  @ObservationIgnored private let openDirectChat: (@MainActor (String) async -> Bool)?

  init(
    rooms: (any RoomLinkRepository)?, openDirectChat: (@MainActor (String) async -> Bool)?
  ) {
    self.rooms = rooms
    self.openDirectChat = openDirectChat
  }

  /// Follows `url` when it is a Matrix link and returns `true`; any other link is left to the system.
  @discardableResult
  func handle(_ url: URL) -> Bool {
    guard let link = MatrixLink(url: url) else { return false }
    errorMessage = nil
    switch link {
    case .user(let id):
      person = id
    case .room(let idOrAlias, let eventId, let via):
      Task { await follow(idOrAlias, eventId: eventId, via: via) }
    }
    return true
  }

  func follow(_ idOrAlias: String, eventId: String?, via: [String]) async {
    guard let rooms else { return }
    do {
      switch try await rooms.target(of: idOrAlias, via: via) {
      case .member(let roomId):
        opening = Opening(roomId: roomId, eventId: eventId)
      case .preview(let preview):
        joining = Joining(preview: preview, via: via, eventId: eventId)
      }
    } catch {
      errorMessage = String(localized: "This chat could not be found.")
    }
  }

  /// Joins the previewed room and opens it.
  func join() async {
    guard let joining, let rooms, !isJoining else { return }
    isJoining = true
    defer { isJoining = false }
    errorMessage = nil
    do {
      let roomId = try await rooms.join(joining.preview.idOrAlias, via: joining.via)
      self.joining = nil
      opening = Opening(roomId: roomId, eventId: joining.eventId)
    } catch {
      errorMessage =
        joining.preview.isPublic
        ? String(localized: "Could not join this chat. Please try again.")
        : String(localized: "This chat is private: someone in it has to invite you.")
    }
  }

  /// Opens the direct chat with the linked person.
  func message(_ userId: String) async {
    person = nil
    guard let openDirectChat else { return }
    if await !openDirectChat(userId) {
      errorMessage = String(localized: "Could not open the chat with \(userId).")
    }
  }

  func clearError() { errorMessage = nil }
}

/// A room the user is not in, before joining, as the Flutter public room preview sheet: picture, name, topic, member
/// count, and Join.
struct JoinRoomSheet: View {
  let joining: LinkRouter.Joining
  let router: LinkRouter
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      VStack(spacing: 14) {
        TwakeAvatar(name: title, size: 88)
        Text(title).font(.title2.weight(.semibold)).multilineTextAlignment(.center)
        Text(members)
          .font(.subheadline)
          .foregroundStyle(SysColors.textSecondary)
        if let topic = joining.preview.topic {
          Text(topic).font(.body).multilineTextAlignment(.center).lineLimit(4)
        }
        if let message = router.errorMessage {
          Text(message).font(.footnote).foregroundStyle(SysColors.error)
            .multilineTextAlignment(.center)
        }
        Spacer(minLength: 8)
        Button {
          Task { await router.join() }
        } label: {
          Group {
            if router.isJoining { ProgressView().tint(.white) } else { Text("Join") }
          }
          .frame(maxWidth: .infinity)
        }
        .buttonStyle(.twakePrimary)
        .disabled(router.isJoining)
      }
      .padding(24)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
      }
    }
    .presentationDetents([.medium])
    .onDisappear { router.clearError() }
  }

  private var title: String { joining.preview.name ?? joining.preview.idOrAlias }

  private var members: String {
    let count = joining.preview.memberCount
    return count == 1 ? "1 member" : "\(count) members"
  }
}
