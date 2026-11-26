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
  public private(set) var typedAddress: ContactAddress?
  public private(set) var selectedAddresses: [ContactAddress] = []
  public private(set) var consent: IdentityConsent?
  public var offersAddressInvites: Bool { identity != nil && identityStatus != .unavailable }
  @ObservationIgnored public var regionCode: String? = Locale.current.region?.identifier
  @ObservationIgnored private let identity: (any IdentityRepository)?
  @ObservationIgnored private let inviteAddressesAction:
    (@MainActor ([ContactAddress]) async -> [ContactAddress])?
  private var identityStatus: IdentityServerStatus?
  @ObservationIgnored private var addressAfterConsent: ContactAddress?

  /// - Parameter onOpen: Opens the chat that was found or created, with its name.
  public init(
    mode: Mode = .direct, repository: any PeopleRepository, debounce: Duration = .milliseconds(300),
    onOpen: @escaping @MainActor (String, String) -> Void,
    invite: (@MainActor ([String]) async -> [String])? = nil,
    identity: (any IdentityRepository)? = nil,
    inviteAddresses: (@MainActor ([ContactAddress]) async -> [ContactAddress])? = nil
  ) {
    self.mode = mode
    self.repository = repository
    self.debounce = debounce
    self.onOpen = onOpen
    self.inviteAction = invite
    self.identity = identity
    self.inviteAddressesAction = inviteAddresses
  }

  /// Invites the picked people into the room (`.invite` mode).
  public func inviteSelected() async {
    guard !selected.isEmpty || !selectedAddresses.isEmpty, !isCreating, let inviteAction else {
      return
    }
    isCreating = true
    defer { isCreating = false }
    errorMessage = nil
    let failed = selected.isEmpty ? [] : await inviteAction(selected.map(\.id))
    let failedAddresses =
      selectedAddresses.isEmpty
      ? [] : await inviteAddressesAction?(selectedAddresses) ?? selectedAddresses
    if failed.isEmpty, failedAddresses.isEmpty {
      didInvite = true
    } else if failed.count == selected.count, failedAddresses.count == selectedAddresses.count {
      errorMessage = localized("Could not invite. Please try again.")
    } else {
      selected = selected.filter { failed.contains($0.id) }
      selectedAddresses = failedAddresses
      let names = (selected.map { $0.displayName ?? $0.id } + failedAddresses.map(\.address))
        .formatted(.list(type: .and))
      errorMessage = localized("Could not invite \(names). The others were invited.")
    }
  }

  public func switchMode(_ mode: Mode) {
    self.mode = mode
    selected = []
    selectedAddresses = []
    errorMessage = nil
  }

  /// Searches now, without waiting; the screen calls it on submit and tests call it directly.
  public func search() async {
    let text = query
    guard !text.trimmingCharacters(in: .whitespaces).isEmpty else {
      results = []
      typedAddress = nil
      return
    }
    isSearching = true
    defer { isSearching = false }
    let address = await addressToOffer(in: text)
    do {
      var found = try await repository.search(text)
      var offered = address
      if let address, await currentIdentityStatus() == .ready,
        let userId = try? await identity?.lookup([address])[address]
      {
        offered = nil
        if !found.contains(where: { $0.id == userId }) {
          found.insert(Person(id: userId, displayName: address.address), at: 0)
        }
      }
      if text == query {
        results = found
        typedAddress = offered
      }
      errorMessage = nil
    } catch {
      errorMessage = localized("Could not search. Please try again.")
    }
  }

  public func isSelected(_ address: ContactAddress) -> Bool {
    selectedAddresses.contains(address)
  }

  public func tap(_ address: ContactAddress) async {
    guard !isCreating else { return }
    if mode != .direct, let index = selectedAddresses.firstIndex(of: address) {
      selectedAddresses.remove(at: index)
      return
    }
    switch await currentIdentityStatus() {
    case .unavailable:
      return
    case .needsConsent(let server, let policies):
      addressAfterConsent = address
      consent = IdentityConsent(server: server, policies: policies)
      return
    case .ready:
      break
    }
    isCreating = true
    errorMessage = nil
    let userId: String?
    do {
      userId = try await identity?.lookup([address])[address]
    } catch {
      isCreating = false
      errorMessage = localized("Could not look up \(address.address). Please try again.")
      return
    }
    if let userId {
      isCreating = false
      let person = Person(id: userId, displayName: address.address)
      if mode == .direct || !selected.contains(person) { await tap(person) }
      return
    }
    switch mode {
    case .group, .broadcast, .invite:
      isCreating = false
      selectedAddresses.append(address)
    case .direct:
      defer { isCreating = false }
      do {
        guard let identity else { return }
        let roomId = try await identity.startDirectChat(inviting: address)
        onOpen(roomId, address.address)
      } catch {
        errorMessage = localized("Could not invite \(address.address). Please try again.")
      }
    }
  }

  public func acceptConsent() async {
    guard let consent, let identity else { return }
    self.consent = nil
    do {
      try await identity.acceptTerms(consent.policies)
      identityStatus = .ready
    } catch {
      addressAfterConsent = nil
      errorMessage = localized("Could not accept the terms. Please try again.")
      return
    }
    if let address = addressAfterConsent {
      addressAfterConsent = nil
      await tap(address)
    }
  }

  public func declineConsent() {
    consent = nil
    addressAfterConsent = nil
  }

  private func addressToOffer(in text: String) async -> ContactAddress? {
    guard identity != nil, let address = ContactAddress.parse(text, regionCode: regionCode),
      await currentIdentityStatus() != .unavailable
    else { return nil }
    return address
  }

  private func currentIdentityStatus() async -> IdentityServerStatus {
    if let identityStatus { return identityStatus }
    guard let identity else { return .unavailable }
    let status = await identity.status()
    if case .needsConsent = status { return status }
    identityStatus = status
    return status
  }

  private func inviteAddresses(intoRoom roomId: String) async {
    guard !selectedAddresses.isEmpty, let identity else { return }
    for address in selectedAddresses {
      try? await identity.invite(address, roomId: roomId)
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
      errorMessage = localized("Could not start the chat. Please try again.")
    }
  }

  /// Leaves the draft chat without creating anything.
  public func discardDraft() {
    draftChat = nil
    draftText = ""
    errorMessage = nil
  }

  public var canCreateGroup: Bool {
    (!selected.isEmpty || !selectedAddresses.isEmpty)
      && !groupName.trimmingCharacters(in: .whitespaces).isEmpty && !isCreating
  }

  public var canCreateBroadcast: Bool { broadcast.canCreate && !isCreating }

  public func createBroadcast() async {
    guard canCreateBroadcast else { return }
    isCreating = true
    defer { isCreating = false }
    do {
      let roomId = try await repository.createBroadcast(broadcast, inviting: selected.map(\.id))
      await inviteAddresses(intoRoom: roomId)
      onOpen(roomId, broadcast.name.trimmingCharacters(in: .whitespaces))
    } catch {
      errorMessage =
        broadcast.access == .open
        ? localized("Could not create the Broadcast. Its address may be taken.")
        : localized("Could not create the Broadcast.")
    }
  }

  public func createGroup() async {
    guard canCreateGroup else { return }
    isCreating = true
    defer { isCreating = false }
    let name = groupName.trimmingCharacters(in: .whitespaces)
    do {
      let roomId = try await repository.createGroup(name: name, inviting: selected.map(\.id))
      await inviteAddresses(intoRoom: roomId)
      onOpen(roomId, name)
    } catch {
      errorMessage = localized("Could not create the group. Please try again.")
    }
  }
}

public struct IdentityConsent: Sendable, Equatable {
  public let server: String
  public let policies: [IdentityPolicy]
}

/// One search is one value: the shell presents the new chat sheet with `sheet(item:)`.
extension PeopleSearchViewModel: Identifiable {
  nonisolated public var id: ObjectIdentifier { ObjectIdentifier(self) }
}
