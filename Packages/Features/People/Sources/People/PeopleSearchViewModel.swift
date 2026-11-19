import Domain
import Foundation
import Observation

/// Search the homeserver's people and start a chat, as the Flutter new chat page (`new_private_chat`) and new group page
/// (`new_group`) do. In direct mode a tap opens the chat with that person; in group mode taps select people, then a name
/// and Create make the group. The Contacts tab uses the direct mode. Typing waits a moment before it searches.
@MainActor @Observable
public final class PeopleSearchViewModel {
  public enum Mode: Equatable {
    case direct
    case group
    /// A Broadcast: a page only moderators post to; the picked people are invited to follow it.
    case broadcast
    /// Picks people to invite into an existing room.
    case invite
  }

  public var query = "" {
    didSet { scheduleSearch() }
  }
  public var groupName = ""
  /// The Broadcast being written, in `.broadcast` mode. Its address follows the name until it is edited.
  public var broadcast = BroadcastDraft() {
    didSet {
      if broadcast.name != oldValue.name, !isSlugEdited {
        broadcast.slug = BroadcastDraft.slug(from: broadcast.name)
      }
    }
  }
  /// The user typed the address: the name no longer changes it.
  @ObservationIgnored public var isSlugEdited = false
  public private(set) var mode: Mode
  public private(set) var results: [Person] = []
  public private(set) var selected: [Person] = []
  public private(set) var isSearching = false
  public private(set) var isCreating = false
  public private(set) var errorMessage: String?
  /// The person a chat is being drafted with: no room exists yet, and the first message creates it.
  public private(set) var draftChat: Person?
  /// The first message of the draft chat.
  public var draftText = ""

  @ObservationIgnored private let repository: any PeopleRepository
  @ObservationIgnored private let onOpen: @MainActor (_ roomId: String, _ name: String) -> Void
  @ObservationIgnored private var searchTask: Task<Void, Never>?
  @ObservationIgnored private let debounce: Duration
  /// Invites the picked people (their Matrix ids) and says whether it worked; for `.invite`.
  @ObservationIgnored private let inviteAction: (@MainActor ([String]) async -> [String])?
  /// Set once the picked people were invited; the invite screen closes.
  public private(set) var didInvite = false

  /// - Parameter onOpen: Opens the chat that was found or created, with its name.
  public init(
    mode: Mode = .direct, repository: any PeopleRepository, debounce: Duration = .milliseconds(300),
    onOpen: @escaping @MainActor (String, String) -> Void,
    invite: (@MainActor ([String]) async -> [String])? = nil
  ) {
    self.mode = mode
    self.repository = repository
    self.debounce = debounce
    self.onOpen = onOpen
    self.inviteAction = invite
  }

  /// Invites the picked people into the room (`.invite` mode).
  public func inviteSelected() async {
    guard !selected.isEmpty, !isCreating, let inviteAction else { return }
    isCreating = true
    defer { isCreating = false }
    errorMessage = nil
    let failed = await inviteAction(selected.map(\.id))
    if failed.isEmpty {
      didInvite = true
    } else if failed.count == selected.count {
      errorMessage = "Could not invite. Please try again."
    } else {
      // The others are in: keep only the people still to invite, by name, so the user can try them again.
      selected = selected.filter { failed.contains($0.id) }
      let names = selected.map { $0.displayName ?? $0.id }.formatted(.list(type: .and))
      errorMessage = "Could not invite \(names). The others were invited."
    }
  }

  public func switchMode(_ mode: Mode) {
    self.mode = mode
    selected = []
    errorMessage = nil
  }

  /// Searches now, without waiting; the screen calls it on submit and tests call it directly.
  public func search() async {
    let text = query
    guard !text.trimmingCharacters(in: .whitespaces).isEmpty else {
      results = []
      return
    }
    isSearching = true
    defer { isSearching = false }
    do {
      let found = try await repository.search(text)
      if text == query { results = found }
      errorMessage = nil
    } catch {
      errorMessage = "Could not search. Please try again."
    }
  }

  private func scheduleSearch() {
    searchTask?.cancel()
    let delay = debounce
    searchTask = Task { [weak self] in
      try? await Task.sleep(for: delay)
      guard !Task.isCancelled else { return }
      await self?.search()
    }
  }

  public func isSelected(_ person: Person) -> Bool { selected.contains(person) }

  /// Direct mode opens the chat; group and invite modes add or remove the person.
  public func tap(_ person: Person) async {
    switch mode {
    case .group, .broadcast, .invite:
      if let index = selected.firstIndex(of: person) {
        selected.remove(at: index)
      } else {
        selected.append(person)
      }
    case .direct:
      guard !isCreating else { return }
      isCreating = true
      defer { isCreating = false }
      errorMessage = nil
      if let roomId = await repository.existingDirectChat(with: person.id) {
        onOpen(roomId, person.name)
      } else {
        // Nobody is invited and no room is made by a tap: the chat is a draft until its first message.
        draftText = ""
        draftChat = person
      }
    }
  }

  /// Starts a draft chat with someone picked elsewhere (a member's profile, the chat list search).
  public func draft(with person: Person) {
    errorMessage = nil
    draftText = ""
    draftChat = person
  }

  public var canSendDraft: Bool {
    draftChat != nil && !isCreating
      && !draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  /// Sends the first message of the draft chat: creates the chat, sends the message and opens the chat.
  public func sendDraft() async {
    guard canSendDraft, let person = draftChat else { return }
    isCreating = true
    defer { isCreating = false }
    errorMessage = nil
    let text = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
    do {
      let roomId = try await repository.startDirectChat(with: person.id, firstMessage: text)
      draftChat = nil
      draftText = ""
      onOpen(roomId, person.name)
    } catch {
      errorMessage = "Could not start the chat. Please try again."
    }
  }

  /// Leaves the draft chat without creating anything.
  public func discardDraft() {
    draftChat = nil
    draftText = ""
    errorMessage = nil
  }

  public var canCreateGroup: Bool {
    !selected.isEmpty && !groupName.trimmingCharacters(in: .whitespaces).isEmpty && !isCreating
  }

  public var canCreateBroadcast: Bool { broadcast.canCreate && !isCreating }

  public func createBroadcast() async {
    guard canCreateBroadcast else { return }
    isCreating = true
    defer { isCreating = false }
    do {
      let roomId = try await repository.createBroadcast(broadcast, inviting: selected.map(\.id))
      onOpen(roomId, broadcast.name.trimmingCharacters(in: .whitespaces))
    } catch {
      errorMessage =
        broadcast.access == .open
        ? "Could not create the Broadcast. Its address may be taken."
        : "Could not create the Broadcast."
    }
  }

  public func createGroup() async {
    guard canCreateGroup else { return }
    isCreating = true
    defer { isCreating = false }
    let name = groupName.trimmingCharacters(in: .whitespaces)
    do {
      let roomId = try await repository.createGroup(name: name, inviting: selected.map(\.id))
      onOpen(roomId, name)
    } catch {
      errorMessage = "Could not create the group. Please try again."
    }
  }
}

/// One search is one value: the shell presents the new chat sheet with `sheet(item:)`.
extension PeopleSearchViewModel: Identifiable {
  nonisolated public var id: ObjectIdentifier { ObjectIdentifier(self) }
}
