import ChatListTestSupport
import Domain
import Foundation
import Testing

@testable import ChatList

@MainActor
struct FoldersTests {
  private actor Folders: FoldersRepository {
    var state: FolderState
    private(set) var saves: [[Folder]] = []
    private(set) var applied: [[FolderTagChange]] = []
    var fails = false

    init(_ state: FolderState) { self.state = state }

    func fail() { fails = true }

    func load() async throws(FoldersError) -> FolderState { state }

    func save(_ shown: [Folder]) async throws(FoldersError) {
      if fails { throw .requestFailed }
      saves.append(shown)
    }

    func apply(_ changes: [FolderTagChange]) async throws(FoldersError) {
      applied.append(changes)
    }
  }

  private func room(_ id: String, direct: Bool = false) -> RoomSummary {
    RoomSummary(
      id: id, name: id, lastMessageText: nil, lastMessageSender: nil, lastActivity: nil,
      isDirect: direct, directUserId: direct ? "@\(id):x" : nil)
  }

  private func waitUntil(_ condition: () -> Bool) async {
    for _ in 0..<10_000 where !condition() { await Task.yield() }
  }

  private func loaded(_ folders: Folders, rooms: [RoomSummary]) async -> (
    ChatListViewModel, Task<Void, Never>
  ) {
    let repository = FakeRoomListRepository()
    let viewModel = ChatListViewModel(repository: repository, folders: folders, logOut: { true })
    let task = Task { await viewModel.start() }
    await waitUntil { repository.isStarted }
    repository.send(rooms)
    await waitUntil { viewModel.state != .loading }
    await viewModel.loadFolders()
    return (viewModel, task)
  }

  @Test func aFolderMadeElsewhereShowsAsAChipAndFiltersTheList() async {
    let folders = Folders(
      FolderState(
        saved: [Folder(name: "Work", include: [.direct])], roomFolders: ["g1": ["Work"]]))
    let (viewModel, task) = await loaded(
      folders, rooms: [room("g1"), room("g2"), room("d1", direct: true)])
    #expect(viewModel.userFolders.map(\.name) == ["Work"])
    viewModel.selectFolder(viewModel.userFolders[0])
    #expect(viewModel.joinedRooms.map(\.id) == ["g1", "d1"])
    viewModel.select(.all)
    #expect(viewModel.selectedFolderId == nil)
    #expect(viewModel.joinedRooms.count == 3)
    task.cancel()
  }

  @Test func aChatIsAddedToAFolderByItsTagAndTakenOutByAnExclusion() async {
    let folders = Folders(FolderState(saved: [Folder(name: "Work", include: [.direct])]))
    let (viewModel, task) = await loaded(folders, rooms: [room("g1"), room("d1", direct: true)])
    let work = viewModel.userFolders[0]
    await viewModel.toggle(room("g1"), in: work)
    #expect(
      await folders.applied.last == [FolderTagChange(roomId: "g1", folderName: "Work", isIn: true)])
    #expect(viewModel.isRoom(room("g1"), in: viewModel.userFolders[0]))
    await viewModel.toggle(room("d1", direct: true), in: viewModel.userFolders[0])
    #expect(viewModel.userFolders[0].exclude == ["d1"])
    #expect(!viewModel.isRoom(room("d1", direct: true), in: viewModel.userFolders[0]))
    task.cancel()
  }

  @Test func theEditorCreatesAFolderWithItsKindsAndPickedChats() async {
    let folders = Folders(FolderState())
    let (viewModel, task) = await loaded(
      folders, rooms: [room("g1"), room("g2"), room("d1", direct: true)])
    var done = 0
    let editor = viewModel.makeFolderEditor { done += 1 }
    #expect(!editor.canSave)
    editor.name = " Team "
    editor.emoji = "👥"
    editor.setIncluded(.direct, true)
    #expect(editor.isPicked(room("d1", direct: true)))
    editor.toggle(room("g2"))
    await editor.save()
    #expect(done == 1)
    let saved = await folders.saves.last ?? []
    let team = saved.first { $0.name == "Team" }
    #expect(team == Folder(name: "Team", emoji: "👥", include: [.direct]))
    #expect(saved.prefix(5).allSatisfy { $0.builtin != nil })
    #expect(
      await folders.applied.last == [FolderTagChange(roomId: "g2", folderName: "Team", isIn: true)])
    #expect(viewModel.userFolders.map(\.title) == ["👥 Team"])
    task.cancel()
  }

  @Test func twoFoldersCannotShareAName() async {
    let folders = Folders(FolderState(saved: [Folder(name: "Work")]))
    let (viewModel, task) = await loaded(folders, rooms: [room("g1")])
    let editor = viewModel.makeFolderEditor {}
    editor.name = "Work"
    #expect(editor.nameError != nil)
    #expect(!editor.canSave)
    let renaming = viewModel.makeFolderEditor(viewModel.userFolders[0]) {}
    #expect(renaming.nameError == nil)
    task.cancel()
  }

  @Test func renamingMovesTheTagsOfItsChats() async {
    let folders = Folders(
      FolderState(saved: [Folder(name: "Old")], roomFolders: ["g1": ["Old"]]))
    let (viewModel, task) = await loaded(folders, rooms: [room("g1"), room("g2")])
    let editor = viewModel.makeFolderEditor(viewModel.userFolders[0]) {}
    #expect(editor.isPicked(room("g1")))
    editor.name = "New"
    await editor.save()
    #expect(
      await folders.applied.last == [
        FolderTagChange(roomId: "g1", folderName: "New", isIn: true),
        FolderTagChange(roomId: "g1", folderName: "Old", isIn: false),
      ])
    #expect(viewModel.userFolders.map(\.name) == ["New"])
    #expect(viewModel.folders(of: room("g1")) == ["New"])
    task.cancel()
  }

  @Test func deletingAFolderUntagsItsChatsAndClearsTheSelection() async {
    let folders = Folders(
      FolderState(
        saved: [Folder(name: "Work"), Folder(name: "Home")], roomFolders: ["g1": ["Work"]]))
    let (viewModel, task) = await loaded(folders, rooms: [room("g1")])
    viewModel.selectFolder(viewModel.userFolders[0])
    await viewModel.deleteFolder(viewModel.userFolders[0])
    #expect(viewModel.selectedFolderId == nil)
    #expect(viewModel.userFolders.map(\.name) == ["Home"])
    #expect(
      await folders.applied.last == [FolderTagChange(roomId: "g1", folderName: "Work", isIn: false)]
    )
    #expect((await folders.saves.last ?? []).contains { $0.name == "Work" } == false)
    task.cancel()
  }

  @Test func foldersAreOrderedAndSaved() async {
    let folders = Folders(FolderState(saved: [Folder(name: "A"), Folder(name: "B")]))
    let (viewModel, task) = await loaded(folders, rooms: [])
    await viewModel.moveFolder(viewModel.userFolders[0], by: 1)
    #expect(viewModel.userFolders.map(\.name) == ["B", "A"])
    #expect((await folders.saves.last ?? []).filter(\.isUser).map(\.name) == ["B", "A"])
    task.cancel()
  }

  @Test func aFailedSaveSaysSoAndReloads() async {
    let folders = Folders(FolderState(saved: [Folder(name: "A"), Folder(name: "B")]))
    let (viewModel, task) = await loaded(folders, rooms: [room("g1")])
    await folders.fail()
    await viewModel.moveFolder(viewModel.userFolders[0], by: 1)
    #expect(viewModel.actionErrorMessage == "Could not update the folders.")
    #expect(viewModel.userFolders.map(\.name) == ["A", "B"])
    task.cancel()
  }
}
