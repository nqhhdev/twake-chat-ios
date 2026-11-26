import Domain
import Foundation
import SwiftUI

/// The composer: the draft, its formatting, mentions, bot commands, reply and edit modes, and sending text and
/// attachments.
extension RoomViewModel {
  /// The commands the draft's "/" word may become.
  public var commandSuggestions: [BotCommand] {
    Array(BotCommand.matching(draft, in: botCommands).prefix(6))
  }

  /// Writes the command's name in the composer, ready for its arguments.
  public func pick(_ command: BotCommand) {
    draft = "/" + command.name + (command.argumentNames.isEmpty ? "" : " ")
  }

  /// "Alice is typing…", "Alice and Bob are typing…", "Alice and 2 others are typing…", or `nil`.
  public var typingText: String? { TypingText.line(for: typingNames) }

  /// Tells the room the user is typing while the draft has text, and stopped once it is empty.
  public func draftDidChange(from old: String, to new: String) async {
    if new.isEmpty { mentions = [] }
    let wasTyping = !old.isEmpty
    let isTyping = !new.isEmpty
    guard wasTyping != isTyping else { return }
    await repository.setTyping(isTyping)
  }

  /// Uploads and sends a picked picture, video or file, as a reply when the composer is replying. The file at
  /// `fileURL` must stay until the upload ends; the caller removes it after.
  public func send(
    attachment kind: OutgoingAttachment.Kind, fileURL: URL, mimeType: String?, size: Int?,
    caption: String? = nil, batchId: String? = nil
  ) async {
    var replyTo: String?
    if case .reply(let eventId, _) = composerMode {
      replyTo = eventId
      composerMode = .new
    }
    errorMessage = nil
    uploadCount += 1
    sendCount += 1
    defer { uploadCount -= 1 }
    do {
      try await repository.sendAttachment(
        OutgoingAttachment(
          kind: kind, fileURL: fileURL, mimeType: mimeType, size: size, caption: caption,
          replyTo: replyTo, batchId: batchId))
    } catch {
      errorMessage = Self.attachmentFailureMessage(error)
    }
  }

  /// Why an attachment was not sent, as the composer shows it.
  static func attachmentFailureMessage(_ error: TimelineError) -> String {
    switch error {
    case .tooLarge: localized("This file is larger than the server allows.")
    case .unsupportedType: localized("This type of file cannot be sent.")
    case .network: localized("Could not reach the server. Check your connection and try again.")
    case .forbidden: localized("You are not allowed to send files in this chat.")
    case .uploadFailed: localized("Could not upload the file. Please try again.")
    case .notSignedIn, .roomNotFound, .unavailable, .requestFailed:
      localized("Could not send the attachment. Please try again.")
    }
  }

  /// Sends what the preview kept, one after another (pictures sent together show as an album), the caption with the
  /// last one, as the Flutter upload manager does. The composer's draft, which the preview offered as the caption, is
  /// cleared; the copied files are deleted once sent.
  func send(
    batch: [AttachmentLoader.Loaded], caption: String, descriptions: [UUID: String] = [:]
  ) async {
    let caption = caption.trimmingCharacters(in: .whitespacesAndNewlines)
    draft = ""
    let limit = await media.maxUploadSize()
    let tooLarge = batch.filter { item in limit.map { (item.size ?? 0) > $0 } ?? false }
    for item in tooLarge { AttachmentLoader.remove(item) }
    let batch = batch.filter { item in !tooLarge.contains { $0.id == item.id } }
    var limitMessage: String?
    if let limit, !tooLarge.isEmpty {
      let size = Self.sizeText(limit) ?? localized("\(limit) bytes")
      limitMessage =
        tooLarge.count == 1
        ? localized("This file is larger than the server allows (\(size)).")
        : localized("\(tooLarge.count) files are larger than the server allows (\(size)).")
    }
    let batchId = Self.albumId(for: batch)
    for (index, item) in batch.enumerated() {
      let isLast = index == batch.count - 1
      await send(
        attachment: item.kind, fileURL: item.fileURL, mimeType: item.mimeType, size: item.size,
        caption: Self.caption(
          of: item, descriptions: descriptions, batchCaption: isLast ? caption : ""),
        batchId: item.isVisual ? batchId : nil)
      AttachmentLoader.remove(item)
    }
    if let limitMessage { errorMessage = limitMessage }
  }

  static func albumId(for batch: [AttachmentLoader.Loaded], make: () -> UUID = UUID.init)
    -> String?
  {
    batch.filter(\.isVisual).count >= 2 ? make().uuidString.lowercased() : nil
  }

  static func caption(
    of item: AttachmentLoader.Loaded, descriptions: [UUID: String], batchCaption: String
  ) -> String? {
    if !batchCaption.isEmpty { return batchCaption }
    let description = descriptions[item.id]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return description.isEmpty ? nil : description
  }

  public var canSend: Bool {
    !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  /// The text after "@" at the end of the draft, while the user is typing a mention; `nil` otherwise.
  public var mentionQuery: String? {
    guard let at = draft.lastIndex(of: "@") else { return nil }
    if at > draft.startIndex, !draft[draft.index(before: at)].isWhitespace { return nil }
    let query = draft[draft.index(after: at)...]
    guard !query.contains(where: \.isNewline), query.count <= 32 else { return nil }
    // A name can hold spaces; two spaces in a row end the mention.
    guard !query.contains("  ") else { return nil }
    return String(query)
  }

  /// The members whose name or Matrix id contains the mention query, at most six. Someone who may notify the room
  /// is also offered « Notify everyone » (`@room`).
  public var mentionSuggestions: [RoomMember] {
    guard let query = mentionQuery?.lowercased() else { return [] }
    let found = members.filter { member in
      query.isEmpty || member.name.lowercased().contains(query)
        || member.id.lowercased().contains(query)
    }
    guard canNotifyRoom else { return Array(found.prefix(6)) }
    if RoomMember.offersEveryoneFirst(for: query) { return [.everyone] + found.prefix(5) }
    return query.isEmpty ? Array(found.prefix(5)) + [.everyone] : Array(found.prefix(6))
  }

  /// Loads the members for the @ suggestions, once, when the user starts a mention.
  public func loadMembersIfNeeded() async {
    guard mentionQuery != nil, !didLoadMembers, let detailsRepository else { return }
    didLoadMembers = true
    members = (try? await detailsRepository.members(roomId: roomId)) ?? []
  }

  /// Replaces the "@query" at the end of the draft with "@Name " and remembers the person.
  public func pickMention(_ member: RoomMember) {
    guard let at = draft.lastIndex(of: "@") else { return }
    let name = Self.mentionName(member)
    draft = String(draft[..<at]) + "@" + name + " "
    // « @room » stays as text: the data layer reads it there, it is no link to a person.
    if member != .everyone, !mentions.contains(member) { mentions.append(member) }
  }

  /// The name a mention shows, without the characters Markdown links use.
  static func mentionName(_ member: RoomMember) -> String {
    member.name.filter { !"[]()".contains($0) }
  }

  /// Turns each picked "@Name" of `text` into a Markdown link to the person, which the data layer sends as a mention.
  static func applyingMentions(_ mentions: [RoomMember], to text: String) -> String {
    var result = text
    for member in mentions {
      let name = mentionName(member)
      result = result.replacingOccurrences(
        of: "@" + name, with: "[\(name)](https://matrix.to/#/\(member.id))")
    }
    return result
  }

  /// Sends the draft as a new message, a reply or an edit; the draft is cleared at once and put back if sending fails.
  public func send() async {
    let typed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !typed.isEmpty else { return }
    let mode = composerMode
    // A new message that starts with « / » is a bot's command, a client command (`/me`, `/shrug`), or a mistake
    // that is not sent, as on the web.
    var prepared = ComposerCommand.message(typed)
    if case .new = mode, BotCommand.command(for: typed, in: botCommands) == nil {
      prepared = ComposerCommand.prepare(typed)
    }
    if case .unknown = prepared {
      errorMessage =
        localized(
          "This command does not exist. Start with “//” to send a text that starts with “/”.")
      return
    }
    let picked = mentions
    mentions = []
    sendCount += 1
    draft = ""
    await repository.setTyping(false)
    composerMode = .new
    errorMessage = nil
    do {
      switch mode {
      case .new:
        if let command = BotCommand.command(for: typed, in: botCommands) {
          try await repository.send(command: command, text: typed)
        } else if case .emote(let action) = prepared {
          try await repository.send(emote: Self.applyingMentions(picked, to: action))
        } else if case .message(let body) = prepared {
          try await repository.send(text: Self.applyingMentions(picked, to: body))
        }
      case .reply(let eventId, _):
        try await repository.reply(text: Self.applyingMentions(picked, to: typed), to: eventId)
      case .edit(let eventId):
        try await repository.edit(eventId: eventId, text: Self.applyingMentions(picked, to: typed))
      }
    } catch {
      draft = typed
      mentions = picked
      composerMode = mode
      errorMessage = localized("Could not send your message. Please try again.")
    }
  }

  /// Writes the format's Markdown around the selected part of the draft, or takes it off; returns what to select
  /// after.
  func format(_ format: TextFormat, selection: Range<String.Index>) -> Range<String.Index> {
    let result = TextFormatting.apply(format, to: draft, selection: offsets(of: selection))
    draft = result.text
    return indices(of: result.selection)
  }

  /// The link the « Add a link » dialog starts from: the one the selection is in, or the selected text.
  func linkTarget(selection: Range<String.Index>) -> LinkTarget {
    TextFormatting.linkTarget(in: draft, selection: offsets(of: selection))
  }

  /// Writes the link over its target and returns the caret after it; `nil`, and the draft unchanged, when `url` is not
  /// a web address.
  func addLink(_ target: LinkTarget, label: String, url: String) -> Range<String.Index>? {
    guard let address = TextFormatting.webAddress(url) else { return nil }
    let result = TextFormatting.link(target, in: draft, label: label, url: address)
    draft = result.text
    return indices(of: result.selection)
  }

  private func offsets(of range: Range<String.Index>) -> Range<Int> {
    let range = range.clamped(to: draft.startIndex..<draft.endIndex)
    let start = draft.distance(from: draft.startIndex, to: range.lowerBound)
    return start..<(start + draft.distance(from: range.lowerBound, to: range.upperBound))
  }

  private func indices(of range: Range<Int>) -> Range<String.Index> {
    let start = draft.index(draft.startIndex, offsetBy: range.lowerBound)
    return start..<draft.index(start, offsetBy: range.count)
  }

  public func reply(to message: TimelineMessage) {
    guard let eventId = message.eventId else { return }
    composerMode = .reply(
      eventId: eventId, to: .init(senderName: message.senderName, text: Self.text(of: message.body))
    )
  }

  /// Puts the user's own text message in the composer to edit it.
  public func edit(_ message: TimelineMessage) {
    guard message.isOwn, let eventId = message.eventId, case .text(let text) = message.body else {
      return
    }
    draft = text
    composerMode = .edit(eventId: eventId)
  }

  public func cancelComposerMode() {
    if case .edit = composerMode { draft = "" }
    composerMode = .new
  }
}
