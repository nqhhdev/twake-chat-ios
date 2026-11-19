import Domain
import Foundation
import SwiftUI

/// A message's menu and selection: react, copy, share, forward, save, report, block and delete.
extension RoomViewModel {
  /// The versions of an edited message, the original first; `nil` in an encrypted chat.
  func editHistory(of message: TimelineMessage) async -> [MessageVersion]? {
    guard let eventId = message.eventId else { return [] }
    return await repository.editHistory(of: eventId)
  }

  public var canSave: Bool { saved != nil }

  func loadSaved() async {
    guard let saved else { return }
    savedEventIds = Set(await saved.savedRefs().filter { $0.roomId == roomId }.map(\.eventId))
  }

  public func isSaved(_ message: TimelineMessage) -> Bool {
    message.eventId.map(savedEventIds.contains) ?? false
  }

  /// Saves the message to Saved messages, or forgets it.
  public func toggleSaved(_ message: TimelineMessage) async {
    guard let saved, let eventId = message.eventId else { return }
    let save = !savedEventIds.contains(eventId)
    do {
      try await saved.setSaved(save, roomId: roomId, eventId: eventId)
      if save { savedEventIds.insert(eventId) } else { savedEventIds.remove(eventId) }
      showToast(save ? "Saved" : "Removed from saved messages")
    } catch {
      errorMessage = "Could not update your saved messages."
    }
  }

  static func reactionBar(recents: [String]) -> [String] {
    var bar: [String] = []
    for key in recents + quickReactions where !bar.contains(key) && !key.isEmpty {
      bar.append(key)
      if bar.count == quickReactions.count { break }
    }
    return bar
  }

  func loadRecentReactions() async {
    reactionBar = Self.reactionBar(recents: await repository.recentReactions())
  }

  /// Sends again the message that failed to send.
  public func retry(_ message: TimelineMessage) async {
    guard message.sendState == .failed, let transactionId = message.transactionId else { return }
    await repository.retrySend(transactionId: transactionId)
    showToast("Sending again")
  }

  /// Shows who sent a reaction.
  func showReactors(_ reaction: TimelineMessage.Reaction) {
    peopleSheet = PeopleSheet(title: "Reacted \(reaction.key)", userIds: reaction.senderIds)
  }

  /// The room's members, for names and pictures in the people sheets.
  func roomMembers() async -> [RoomMember] {
    if members.isEmpty, let detailsRepository {
      members = (try? await detailsRepository.members(roomId: roomId)) ?? []
    }
    return members
  }

  /// Shows who has seen a message.
  func showReaders(of message: TimelineMessage) {
    peopleSheet = PeopleSheet(title: "Seen by", userIds: message.readerIds)
  }

  public func startSelecting(_ message: TimelineMessage) {
    guard let eventId = message.eventId else { return }
    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
      composerMode = .new
      selectedMessages = [eventId: message]
      isSelectingMessages = true
    }
  }

  public func toggleSelection(_ message: TimelineMessage) {
    guard let eventId = message.eventId else { return }
    if selectedMessages.removeValue(forKey: eventId) == nil { selectedMessages[eventId] = message }
  }

  public func isSelected(_ message: TimelineMessage) -> Bool {
    message.eventId.map { selectedMessages[$0] != nil } ?? false
  }

  public func endSelecting() {
    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
      isSelectingMessages = false
      selectedMessages = [:]
    }
  }

  /// The picked messages, oldest first.
  public var orderedSelection: [TimelineMessage] {
    selectedMessages.values.sorted { $0.date < $1.date }
  }

  /// Every picked message may be deleted by the user.
  public var canDeleteSelection: Bool {
    !selectedMessages.isEmpty && selectedMessages.values.allSatisfy(canDelete)
  }

  /// The text of the picked messages, oldest first, each with its sender, as Telegram copies several messages.
  public var selectionText: String {
    orderedSelection.compactMap { message in
      Self.text(of: message.body).map { "\(message.senderName): \($0)" }
    }.joined(separator: "\n")
  }

  public func copySelection() {
    UIPasteboard.general.string = selectionText
    showToast(selectedMessages.count == 1 ? "Copied" : "Copied \(selectedMessages.count) messages")
    endSelecting()
  }

  public func deleteSelection() async {
    guard canDeleteSelection else { return }
    let messages = orderedSelection
    endSelecting()
    for message in messages { await delete(message) }
  }

  /// Forwards several messages to one room, oldest first.
  public func forward(_ messages: [TimelineMessage], to room: RoomSummary) async {
    var failed = false
    for message in messages {
      guard let eventId = message.eventId else { continue }
      do { try await repository.forward(eventId: eventId, to: room.id) } catch { failed = true }
    }
    endSelecting()
    if failed {
      errorMessage = "Could not forward every message."
    } else {
      showToast("Forwarded to \(room.name)")
    }
  }

  public func forward(_ message: TimelineMessage, to room: RoomSummary) async {
    guard let eventId = message.eventId else { return }
    do {
      try await repository.forward(eventId: eventId, to: room.id)
      showToast("Forwarded to \(room.name)")
    } catch {
      errorMessage = "Could not forward the message."
    }
  }

  /// Reports a message to the server's moderators.
  public func report(_ message: TimelineMessage, reason: String) async {
    guard let eventId = message.eventId else { return }
    let reason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
    do {
      try await repository.report(eventId: eventId, reason: reason.isEmpty ? nil : reason)
      showToast("Reported")
    } catch {
      errorMessage = "Could not report the message. Please try again."
    }
  }

  /// Blocks the message's sender: nothing from them shows any more, in any room.
  public func block(_ message: TimelineMessage) async {
    do {
      try await repository.ignore(userId: message.senderId)
      showToast("Blocked \(message.senderName)")
      if message.senderId == directUserId {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
          blockedUserId = message.senderId
        }
      }
    } catch {
      errorMessage = "Could not block \(message.senderName). Please try again."
    }
  }

  /// The user may delete this message: their own, or anyone's as a moderator. Their own message that is not sent
  /// yet (still sending, or failed) is discarded instead, so it never leaves the device.
  public func canDelete(_ message: TimelineMessage) -> Bool {
    if message.eventId == nil { return message.isOwn && message.transactionId != nil }
    guard message.body != .redacted else { return false }
    return message.isOwn || canRedactOthers
  }

  /// The `matrix.to` link to the message, to share it outside the app; `nil` before it is sent.
  public func link(to message: TimelineMessage) -> URL? {
    guard let eventId = message.eventId else { return nil }
    let via = MatrixLink.server(of: message.senderId).map { [$0] } ?? []
    return MatrixLink.room(idOrAlias: roomId, eventId: eventId, via: via).url
  }

  /// Copies the message's link and confirms it.
  public func copyLink(to message: TimelineMessage) {
    guard let url = link(to: message) else { return }
    UIPasteboard.general.url = url
    showToast("Link copied")
  }

  public func delete(_ message: TimelineMessage) async {
    guard canDelete(message) else { return }
    do {
      if let eventId = message.eventId {
        try await repository.redact(eventId: eventId)
      } else if let transactionId = message.transactionId {
        try await repository.discardUnsent(transactionId: transactionId)
      }
    } catch {
      errorMessage = "Could not delete the message."
    }
  }

  public func toggleReaction(_ key: String, on message: TimelineMessage) async {
    guard let eventId = message.eventId else { return }
    let adds = !message.reactions.contains { $0.key == key && $0.includesOwn }
    do {
      try await repository.toggleReaction(key, on: eventId)
      if adds {
        reactionBar = Self.reactionBar(recents: [key] + reactionBar)
        await repository.addRecentReaction(key)
      }
    } catch {
      errorMessage = "Could not send the reaction."
    }
  }

  /// Saves a message's file in a temporary folder to open or share it; `nil` (with a message) when it cannot be loaded.
  public func file(of message: TimelineMessage) async -> URL? {
    guard let reference = message.media else { return nil }
    do {
      return try await media.file(reference, filename: Self.fileName(of: message))
    } catch {
      errorMessage = "Could not download the file."
      return nil
    }
  }

  /// Downloads the messages' pictures, videos or files (every picture of an album) for the share sheet, as the Flutter
  /// message menu's Share and Save do. They download together and keep the album's order. Nothing is offered if one
  /// download fails; the error says so.
  func share(_ messages: [TimelineMessage]) async {
    guard !messages.isEmpty, !isPreparingShare else { return }
    isPreparingShare = true
    defer { isPreparingShare = false }
    let found = await withTaskGroup(of: (Int, URL?).self) { group in
      for (index, message) in messages.enumerated() {
        group.addTask { (index, await self.file(of: message)) }
      }
      var urls = [URL?](repeating: nil, count: messages.count)
      for await (index, url) in group { urls[index] = url }
      return urls
    }
    let urls = found.compactMap { $0 }
    if urls.count == messages.count { sharedFiles = DownloadedFiles(urls: urls) }
  }

  /// The name a message's file is saved under.
  public static func fileName(of message: TimelineMessage) -> String {
    switch message.body {
    case .file(let name): name
    case .image: "image"
    case .video: "video"
    case .audio: "audio"
    default: "file"
    }
  }

  /// "1.2 MB" for a file's size, as the Flutter file bubble shows it.
  public static func sizeText(_ bytes: Int?) -> String? {
    bytes.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) }
  }

  /// The text a message's Copy action copies, or `nil` for a message without text.
  public static func text(of body: TimelineMessage.Body) -> String? {
    switch body {
    case .text(let text), .emote(let text), .notice(let text), .location(let text, _): text
    case .image(let caption), .video(let caption), .audio(let caption): caption
    case .file(let name): name
    case .poll(let question): question
    case .sticker, .redacted, .unableToDecrypt, .unsupported: nil
    }
  }
}
