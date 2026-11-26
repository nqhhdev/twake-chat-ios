import Foundation

public struct Folder: Sendable, Equatable, Identifiable {
  public enum Builtin: String, Sendable, CaseIterable {
    case unread, broadcasts, directs, spaces, favourites
  }

  public enum ChatType: String, Sendable, CaseIterable {
    case direct, group, broadcast, bot
  }

  public var name: String
  public var builtin: Builtin?
  public var isHidden: Bool
  public var emoji: String?
  public var color: String?
  public var include: [ChatType]
  public var exclude: [String]

  public init(
    name: String, builtin: Builtin? = nil, isHidden: Bool = false, emoji: String? = nil,
    color: String? = nil, include: [ChatType] = [], exclude: [String] = []
  ) {
    self.name = name
    self.builtin = builtin
    self.isHidden = isHidden
    self.emoji = emoji
    self.color = color
    self.include = include
    self.exclude = exclude
  }

  public var id: String { builtin.map { "builtin." + $0.rawValue } ?? "folder." + name }

  public var isUser: Bool { builtin == nil }

  public var title: String { emoji.map { "\($0) \(name)" } ?? name }
}

public struct FolderTagChange: Sendable, Equatable {
  public let roomId: String
  public let folderName: String
  public let isIn: Bool

  public init(roomId: String, folderName: String, isIn: Bool) {
    self.roomId = roomId
    self.folderName = folderName
    self.isIn = isIn
  }

  public var tag: String { FolderContent.tagPrefix + folderName }
}

public struct FolderState: Sendable, Equatable {
  public var saved: [Folder]
  public var roomFolders: [String: [String]]

  public init(saved: [Folder] = [], roomFolders: [String: [String]] = [:]) {
    self.saved = saved
    self.roomFolders = roomFolders
  }

  public var shown: [Folder] {
    Folder.list(saved: saved, taggedNames: roomFolders.values.flatMap { $0 })
  }
}

public enum FolderContent {
  public static let accountDataType = "app.twake.chat.folders"
  public static let tagPrefix = "u."
  public static let tagEventType = "m.tag"
  static let knownKeys: Set<String> = [
    "builtin", "name", "emoji", "color", "hidden", "include", "exclude",
  ]

  public static func read(_ content: [String: Any]?) -> [Folder] {
    guard let list = content?["folders"] as? [Any] else { return [] }
    var kinds: Set<Folder.Builtin> = []
    var names: Set<String> = []
    var folders: [Folder] = []
    for case let item as [String: Any] in list {
      if isUnknownBuiltin(item) { continue }
      let name = item["name"] as? String
      let emoji = (item["emoji"] as? String).flatMap { $0.isEmpty ? nil : $0 }
      let color = (item["color"] as? String).flatMap { isColor($0) ? $0 : nil }
      if let raw = item["builtin"] as? String, let kind = Folder.Builtin(rawValue: raw) {
        guard kinds.insert(kind).inserted else { continue }
        folders.append(
          Folder(
            name: name?.trimmingCharacters(in: .whitespaces) ?? "", builtin: kind,
            isHidden: item["hidden"] as? Bool == true, emoji: emoji, color: color))
      } else if let name, !name.trimmingCharacters(in: .whitespaces).isEmpty,
        names.insert(name).inserted
      {
        let include = (item["include"] as? [Any])?.compactMap { $0 as? String } ?? []
        folders.append(
          Folder(
            name: name, emoji: emoji, color: color,
            include: Folder.ChatType.allCases.filter { include.contains($0.rawValue) },
            exclude: (item["exclude"] as? [Any])?.compactMap { $0 as? String } ?? []))
      }
    }
    return folders
  }

  public static func write(_ folders: [Folder], current: [String: Any]?) -> [String: Any] {
    let items = (current?["folders"] as? [Any])?.compactMap { $0 as? [String: Any] } ?? []
    var content = current ?? [:]
    content["folders"] =
      folders.map { folder in
        unknownFields(of: folder, in: items).merging(encode(folder)) { _, new in new }
      } + items.filter(isUnknownBuiltin)
    return content
  }

  public static func folderNames(fromTags tags: some Sequence<String>) -> [String] {
    tags.filter { $0.hasPrefix(tagPrefix) && $0.count > tagPrefix.count }
      .map { String($0.dropFirst(tagPrefix.count)) }
  }

  public static func state(fromSync response: [String: Any]) -> FolderState {
    let global = (response["account_data"] as? [String: Any])?["events"] as? [Any] ?? []
    let content =
      global.lazy.compactMap { $0 as? [String: Any] }
      .first { $0["type"] as? String == accountDataType }?["content"] as? [String: Any]
    let joined = (response["rooms"] as? [String: Any])?["join"] as? [String: Any] ?? [:]
    var roomFolders: [String: [String]] = [:]
    for (roomId, value) in joined {
      let events = ((value as? [String: Any])?["account_data"] as? [String: Any])?["events"]
      let tags =
        (events as? [Any])?.lazy.compactMap { $0 as? [String: Any] }
        .first { $0["type"] as? String == tagEventType }
        .flatMap { ($0["content"] as? [String: Any])?["tags"] as? [String: Any] }
      let names = folderNames(fromTags: (tags ?? [:]).keys.sorted())
      if !names.isEmpty { roomFolders[roomId] = names }
    }
    return FolderState(saved: read(content), roomFolders: roomFolders)
  }

  static func isColor(_ value: String) -> Bool {
    value.count == 7 && value.hasPrefix("#") && value.dropFirst().allSatisfy(\.isHexDigit)
  }

  static func isUnknownBuiltin(_ item: [String: Any]) -> Bool {
    guard let kind = item["builtin"] else { return false }
    return (kind as? String).flatMap(Folder.Builtin.init(rawValue:)) == nil
  }

  static func unknownFields(of folder: Folder, in items: [[String: Any]]) -> [String: Any] {
    let match = items.first { item in
      if let builtin = folder.builtin { return item["builtin"] as? String == builtin.rawValue }
      return item["builtin"] == nil && item["name"] as? String == folder.name
    }
    return (match ?? [:]).filter { !knownKeys.contains($0.key) }
  }

  static func encode(_ folder: Folder) -> [String: Any] {
    if let builtin = folder.builtin {
      if folder.isHidden { return ["builtin": builtin.rawValue, "hidden": true] }
      var item: [String: Any] = ["builtin": builtin.rawValue]
      if !folder.name.isEmpty { item["name"] = folder.name }
      if let emoji = folder.emoji { item["emoji"] = emoji }
      if let color = folder.color { item["color"] = color }
      return item
    }
    var item: [String: Any] = ["name": folder.name]
    if let emoji = folder.emoji { item["emoji"] = emoji }
    if let color = folder.color { item["color"] = color }
    if !folder.include.isEmpty { item["include"] = folder.include.map(\.rawValue) }
    if !folder.exclude.isEmpty { item["exclude"] = folder.exclude }
    return item
  }
}

extension Folder {
  public static func chatType(of room: RoomSummary) -> ChatType? {
    if room.isSpace { return nil }
    if room.isDirect {
      let userId = room.directUserId ?? ""
      return userId.hasPrefix("@bot_") || userId.hasPrefix("@hermes_") ? .bot : .direct
    }
    return room.isBroadcast ? .broadcast : .group
  }

  public func contains(_ room: RoomSummary, folders: [String]) -> Bool {
    guard isUser, !room.isSpace, !exclude.contains(room.id) else { return false }
    if folders.contains(name) { return true }
    return Self.chatType(of: room).map(include.contains) ?? false
  }

  public static func list(saved: [Folder], taggedNames: some Sequence<String>) -> [Folder] {
    let known = Set(saved.filter(\.isUser).map(\.name))
    let tagged = Set(taggedNames).subtracting(known).sorted()
    let savedKinds = Set(saved.compactMap(\.builtin))
    return Builtin.allCases.filter { !savedKinds.contains($0) }.map {
      Folder(name: "", builtin: $0)
    }
      + saved.filter { !$0.isHidden } + tagged.map { Folder(name: $0) }
  }

  public static func withHiddenBuiltins(_ folders: [Folder]) -> [Folder] {
    let shown = folders.filter { !$0.isHidden }
    let shownKinds = Set(shown.compactMap(\.builtin))
    return shown
      + Builtin.allCases.filter { !shownKinds.contains($0) }.map {
        Folder(name: "", builtin: $0, isHidden: true)
      }
  }

  public static func planEdit(
    folder: Folder, previous: Folder?, picked: Set<String>, chats: [RoomSummary],
    roomFolders: [String: [String]]
  ) -> (folder: Folder, changes: [FolderTagChange]) {
    let previousName = previous?.name
    let isRenamed = previousName != nil && previousName != folder.name
    func isOfKind(_ chat: RoomSummary) -> Bool {
      chatType(of: chat).map(folder.include.contains) ?? false
    }
    var changes: [FolderTagChange] = []
    for chat in chats {
      let wasIn = previousName.map { (roomFolders[chat.id] ?? []).contains($0) } ?? false
      let isIn = picked.contains(chat.id) && !isOfKind(chat)
      if isIn && (!wasIn || isRenamed) {
        changes.append(FolderTagChange(roomId: chat.id, folderName: folder.name, isIn: true))
      }
      if let previousName, wasIn && (!isIn || isRenamed) {
        changes.append(FolderTagChange(roomId: chat.id, folderName: previousName, isIn: false))
      }
    }
    let listed = Set(chats.map(\.id))
    var edited = folder
    edited.exclude =
      (previous?.exclude ?? []).filter { !listed.contains($0) }
      + chats.filter { !picked.contains($0.id) && isOfKind($0) }.map(\.id)
    return (edited, changes)
  }

  public static func moving(_ id: String, by offset: Int, in folders: [Folder]) -> [Folder] {
    let userIndices = folders.indices.filter { folders[$0].isUser }
    guard let position = userIndices.firstIndex(where: { folders[$0].id == id }) else {
      return folders
    }
    let target = position + offset
    guard userIndices.indices.contains(target) else { return folders }
    var result = folders
    result.swapAt(userIndices[position], userIndices[target])
    return result
  }
}
