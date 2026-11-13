import Domain
import Foundation

/// A hand-written `MediaRepository` for tests (ADR 0010): answers every call with `result` and records the files
/// asked for.
public final class FakeMediaRepository: MediaRepository, @unchecked Sendable {
  private let lock = NSLock()
  private var _result: Result<Data, MediaError> = .success(Data())
  private var _fileNames: [String] = []

  public init() {}

  public var result: Result<Data, MediaError> {
    get { lock.withLock { _result } }
    set { lock.withLock { _result = newValue } }
  }

  public var fileNames: [String] { lock.withLock { _fileNames } }

  public func thumbnail(_ media: MediaReference, width: Int, height: Int) async throws(MediaError)
    -> Data
  {
    try result.get()
  }

  public func content(_ media: MediaReference) async throws(MediaError) -> Data {
    try result.get()
  }

  public func file(_ media: MediaReference, filename: String) async throws(MediaError) -> URL {
    lock.withLock { _fileNames.append(filename) }
    _ = try result.get()
    return FileManager.default.temporaryDirectory.appending(path: filename)
  }
}
