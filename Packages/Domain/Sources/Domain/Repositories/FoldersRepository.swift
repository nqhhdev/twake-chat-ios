public enum FoldersError: Error, Sendable, Equatable {
  case notSignedIn
  case requestFailed
}

public protocol FoldersRepository: Sendable {
  func load() async throws(FoldersError) -> FolderState
  func save(_ shown: [Folder]) async throws(FoldersError)
  func apply(_ changes: [FolderTagChange]) async throws(FoldersError)
}
