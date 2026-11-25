import Domain
import Foundation
import Photos

/// A downloaded picture or video to add to Photos.
enum PhotoLibraryItem: Equatable, Sendable {
  case picture(URL)
  case video(URL)

  /// The item for a picture or video message saved at `url`; `nil` for any other message.
  init?(_ message: TimelineMessage, file url: URL) {
    switch message.body {
    case .image: self = .picture(url)
    case .video: self = .video(url)
    default: return nil
    }
  }
}

/// Why nothing was added to Photos.
enum PhotoLibraryError: Error, Equatable {
  /// The user did not allow the app to add to Photos.
  case accessDenied
  case saveFailed
}

/// Adds pictures and videos to the user's photo library. A protocol, so tests never reach Photos.
protocol PhotoLibrarySaving: Sendable {
  /// Asks for add-only access the first time, then adds every item in one change, or none of them.
  func add(_ items: [PhotoLibraryItem]) async throws(PhotoLibraryError)
}

/// The system photo library, with add-only access (`NSPhotoLibraryAddUsageDescription`): the app can add to Photos
/// but never read it.
struct SystemPhotoLibrary: PhotoLibrarySaving {
  func add(_ items: [PhotoLibraryItem]) async throws(PhotoLibraryError) {
    let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
    guard status == .authorized || status == .limited else { throw .accessDenied }
    do {
      try await PHPhotoLibrary.shared().performChanges {
        for item in items {
          let request = PHAssetCreationRequest.forAsset()
          switch item {
          case .picture(let url): request.addResource(with: .photo, fileURL: url, options: nil)
          case .video(let url): request.addResource(with: .video, fileURL: url, options: nil)
          }
        }
      }
    } catch {
      throw .saveFailed
    }
  }
}

/// What Save to Photos tells the user.
enum SaveToPhotosOutcome: Equatable {
  case saved(count: Int)
  case accessDenied
  /// The download or the save failed.
  case failed

  var isSaved: Bool {
    if case .saved = self { true } else { false }
  }

  var text: String {
    switch self {
    case .saved(count: 1): "Saved to Photos"
    case .saved(let count): "Saved \(count) items to Photos"
    case .accessDenied: "Allow Twake Chat to add to Photos in Settings."
    case .failed: "Could not save to Photos."
    }
  }

  /// Adds `items` to `library`.
  static func saving(_ items: [PhotoLibraryItem], to library: any PhotoLibrarySaving) async -> Self
  {
    do {
      try await library.add(items)
      return .saved(count: items.count)
    } catch .accessDenied {
      return .accessDenied
    } catch {
      return .failed
    }
  }

  /// Downloads the viewer's picture, then adds it to `library`.
  static func saving(
    picture media: MediaReference, from repository: any MediaRepository,
    to library: any PhotoLibrarySaving
  ) async -> Self {
    guard let url = try? await repository.file(media, filename: "image") else { return .failed }
    return await saving([.picture(url)], to: library)
  }
}

extension RoomViewModel {
  /// Whether the message menu offers Save to Photos: every message is a picture or a video with its file.
  static func canSaveToPhotos(_ messages: [TimelineMessage]) -> Bool {
    !messages.isEmpty
      && messages.allSatisfy { message in
        guard message.media != nil else { return false }
        return switch message.body {
        case .image, .video: true
        default: false
        }
      }
  }

  /// Downloads the pictures and videos (every picture of an album) and adds them to Photos, as the Flutter message
  /// menu's Save does. They download together, in the album's order, with Share's spinner. A toast says they were
  /// saved; the error says why not. Nothing is added if one download fails.
  func saveToPhotos(
    _ messages: [TimelineMessage], library: any PhotoLibrarySaving = SystemPhotoLibrary()
  ) async {
    guard Self.canSaveToPhotos(messages), !isPreparingShare else { return }
    isPreparingShare = true
    defer { isPreparingShare = false }
    let found = await withTaskGroup(of: (Int, PhotoLibraryItem?).self) { group in
      for (index, message) in messages.enumerated() {
        group.addTask {
          (index, await self.file(of: message).flatMap { PhotoLibraryItem(message, file: $0) })
        }
      }
      var items = [PhotoLibraryItem?](repeating: nil, count: messages.count)
      for await (index, item) in group { items[index] = item }
      return items
    }
    let items = found.compactMap { $0 }
    guard items.count == messages.count else { return }
    let outcome = await SaveToPhotosOutcome.saving(items, to: library)
    if outcome.isSaved {
      showToast(outcome.text)
    } else {
      errorMessage = outcome.text
    }
  }
}
