import Domain
import SwiftUI

extension ChatListViewModel {
  public var hasFolders: Bool { foldersRepository != nil }

  public var userFolders: [Folder] { folderState.shown.filter(\.isUser) }

  public var selectedFolder: Folder? {
    selectedFolderId.flatMap { id in userFolders.first { $0.id == id } }
  }

  public func folders(of room: RoomSummary) -> [String] { folderState.roomFolders[room.id] ?? [] }

  func isInSelectedFolder(_ room: RoomSummary) -> Bool {
    guard let folder = selectedFolder else { return true }
    return folder.contains(room, folders: folders(of: room))
  }

  public func select(_ filter: Filter) {
    selectedFolderId = nil
    self.filter = filter
  }

  public func selectFolder(_ folder: Folder) {
    filter = .all
    selectedFolderId = folder.id
  }

  public func loadFolders() async {
    guard let foldersRepository, let state = try? await foldersRepository.load() else { return }
    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { folderState = state }
  }

  public func isRoom(_ room: RoomSummary, in folder: Folder) -> Bool {
    folder.contains(room, folders: folders(of: room))
  }

  public func toggle(_ room: RoomSummary, in folder: Folder) async {
    let picked: Set<String> = isRoom(room, in: folder) ? [] : [room.id]
    await saveFolder(folder, previous: folder, picked: picked, chats: [room])
  }

  @discardableResult
  public func saveFolder(
    _ folder: Folder, previous: Folder?, picked: Set<String>, chats: [RoomSummary]
  ) async -> Bool {
    guard let foldersRepository else { return false }
    let plan = Folder.planEdit(
      folder: folder, previous: previous, picked: picked, chats: chats,
      roomFolders: folderState.roomFolders)
    var shown = folderState.shown
    if let previous, let index = shown.firstIndex(where: { $0.id == previous.id }) {
      shown[index] = plan.folder
    } else {
      shown.append(plan.folder)
    }
    return await commit(shown: shown, changes: plan.changes, foldersRepository)
  }

  public func deleteFolder(_ folder: Folder) async {
    guard let foldersRepository, folder.isUser else { return }
    let shown = folderState.shown.filter { $0.id != folder.id }
    let changes = folderState.roomFolders.filter { $0.value.contains(folder.name) }.keys.sorted()
      .map { FolderTagChange(roomId: $0, folderName: folder.name, isIn: false) }
    if selectedFolderId == folder.id { selectedFolderId = nil }
    await commit(shown: shown, changes: changes, foldersRepository)
  }

  public func moveFolder(_ folder: Folder, by offset: Int) async {
    guard let foldersRepository else { return }
    let shown = Folder.moving(folder.id, by: offset, in: folderState.shown)
    guard shown != folderState.shown else { return }
    await commit(shown: shown, changes: [], foldersRepository)
  }

  @discardableResult
  private func commit(
    shown: [Folder], changes: [FolderTagChange], _ repository: any FoldersRepository
  ) async -> Bool {
    actionErrorMessage = nil
    do {
      try await repository.save(shown)
      try await repository.apply(changes)
    } catch {
      actionErrorMessage = "Could not update the folders."
      await loadFolders()
      return false
    }
    var roomFolders = folderState.roomFolders
    for change in changes {
      var names = roomFolders[change.roomId] ?? []
      names.removeAll { $0 == change.folderName }
      if change.isIn { names.append(change.folderName) }
      roomFolders[change.roomId] = names.isEmpty ? nil : names
    }
    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
      folderState = FolderState(saved: Folder.withHiddenBuiltins(shown), roomFolders: roomFolders)
    }
    return true
  }

  public func makeFolderEditor(_ folder: Folder? = nil, onDone: @escaping @MainActor () -> Void)
    -> FolderEditorViewModel
  {
    FolderEditorViewModel(folder: folder, list: self, onDone: onDone)
  }
}

@MainActor @Observable
public final class FolderEditorViewModel: Identifiable {
  public var name: String
  public var emoji: String
  public private(set) var include: Set<Folder.ChatType>
  public var picked: Set<String>
  public var query = ""
  public private(set) var isSaving = false
  public private(set) var errorMessage: String?
  public let previous: Folder?

  @ObservationIgnored private let list: ChatListViewModel
  @ObservationIgnored private let onDone: @MainActor () -> Void

  init(folder: Folder?, list: ChatListViewModel, onDone: @escaping @MainActor () -> Void) {
    previous = folder
    name = folder?.name ?? ""
    emoji = folder?.emoji ?? ""
    include = Set(folder?.include ?? [])
    picked = Set(
      folder.map { folder in list.allChats.filter { list.isRoom($0, in: folder) }.map(\.id) } ?? [])
    self.list = list
    self.onDone = onDone
  }

  public var chats: [RoomSummary] {
    let text = query.trimmingCharacters(in: .whitespaces)
    guard !text.isEmpty else { return list.allChats }
    return list.allChats.filter { $0.name.localizedCaseInsensitiveContains(text) }
  }

  public var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

  public var nameError: String? {
    let taken = list.userFolders.contains { $0.name == trimmedName && $0.id != previous?.id }
    return taken ? "A folder has this name already." : nil
  }

  public var canSave: Bool { !trimmedName.isEmpty && nameError == nil && !isSaving }

  public func isPicked(_ chat: RoomSummary) -> Bool { picked.contains(chat.id) }

  public func toggle(_ chat: RoomSummary) {
    if picked.contains(chat.id) { picked.remove(chat.id) } else { picked.insert(chat.id) }
  }

  public func setIncluded(_ type: Folder.ChatType, _ isOn: Bool) {
    let ofType = Set(list.allChats.filter { Folder.chatType(of: $0) == type }.map(\.id))
    if isOn {
      include.insert(type)
      picked.formUnion(ofType)
    } else {
      include.remove(type)
      picked.subtract(ofType)
    }
  }

  public func save() async {
    guard canSave else { return }
    isSaving = true
    defer { isSaving = false }
    errorMessage = nil
    let emoji = emoji.trimmingCharacters(in: .whitespaces)
    let folder = Folder(
      name: trimmedName, emoji: emoji.isEmpty ? nil : emoji, color: previous?.color,
      include: Folder.ChatType.allCases.filter(include.contains), exclude: previous?.exclude ?? [])
    if await list.saveFolder(folder, previous: previous, picked: picked, chats: list.allChats) {
      onDone()
    } else {
      errorMessage = "Could not save the folder."
    }
  }
}

extension ChatListViewModel {
  var allChats: [RoomSummary] { allJoinedRooms.filter { !$0.isSpace && !$0.isArchived } }
}

extension Folder.ChatType {
  var title: String {
    switch self {
    case .direct: "Direct chats"
    case .group: "Groups"
    case .broadcast: "Broadcasts"
    case .bot: "Bots"
    }
  }
}
