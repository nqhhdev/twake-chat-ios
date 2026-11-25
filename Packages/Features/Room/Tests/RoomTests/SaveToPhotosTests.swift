import Domain
import Foundation
import RoomTestSupport
import Testing

@testable import Room

/// Records what would be added to Photos and answers with `error`, so the tests never reach the photo library.
private final class FakePhotoLibrary: PhotoLibrarySaving, @unchecked Sendable {
  private let lock = NSLock()
  private var _added: [[PhotoLibraryItem]] = []
  private let error: PhotoLibraryError?

  init(error: PhotoLibraryError? = nil) { self.error = error }

  var added: [[PhotoLibraryItem]] { lock.withLock { _added } }

  func add(_ items: [PhotoLibraryItem]) async throws(PhotoLibraryError) {
    if let error { throw error }
    lock.withLock { _added.append(items) }
  }
}

@MainActor
struct SaveToPhotosTests {
  private let reference = MediaReference(source: "{}", mimeType: "image/jpeg", size: 1_200)
  private let folder = FileManager.default.temporaryDirectory

  private func message(_ body: TimelineMessage.Body, media: Bool = true) -> TimelineMessage {
    TimelineMessage(
      eventId: "$1", senderId: "@bob:example.org", senderName: "Bob", isOwn: false, date: .now,
      body: body, media: media ? reference : nil)
  }

  private func viewModel(_ media: FakeMediaRepository = FakeMediaRepository()) -> RoomViewModel {
    RoomViewModel(
      roomId: "!r", roomName: "Team", repository: FakeTimelineRepository(), media: media)
  }

  @Test func onlyPicturesAndVideosWithAFileCanBeSaved() {
    #expect(RoomViewModel.canSaveToPhotos([message(.image(caption: nil))]))
    #expect(RoomViewModel.canSaveToPhotos([message(.video(caption: nil))]))
    #expect(!RoomViewModel.canSaveToPhotos([message(.file(name: "report.pdf"))]))
    #expect(!RoomViewModel.canSaveToPhotos([message(.image(caption: nil), media: false)]))
    #expect(!RoomViewModel.canSaveToPhotos([message(.image(caption: nil)), message(.text("hi"))]))
    #expect(!RoomViewModel.canSaveToPhotos([]))
  }

  @Test func aPictureAndAVideoAreSavedAsTheirKind() async {
    let library = FakePhotoLibrary()
    let viewModel = viewModel()
    await viewModel.saveToPhotos(
      [message(.image(caption: nil)), message(.video(caption: nil))], library: library)
    #expect(
      library.added == [
        [.picture(folder.appending(path: "image")), .video(folder.appending(path: "video"))]
      ])
    #expect(viewModel.toast == "Saved 2 items to Photos")
    #expect(!viewModel.isPreparingShare)
  }

  @Test func oneSavedPictureSaysSo() async {
    let viewModel = viewModel()
    await viewModel.saveToPhotos([message(.image(caption: nil))], library: FakePhotoLibrary())
    #expect(viewModel.toast == "Saved to Photos")
    #expect(viewModel.errorMessage == nil)
  }

  @Test func refusedAccessSaysWhereToAllowIt() async {
    let viewModel = viewModel()
    await viewModel.saveToPhotos(
      [message(.image(caption: nil))], library: FakePhotoLibrary(error: .accessDenied))
    #expect(viewModel.errorMessage == "Allow Twake Chat to add to Photos in Settings.")
    #expect(viewModel.toast == nil)
  }

  @Test func aFailedSaveShowsAnError() async {
    let viewModel = viewModel()
    await viewModel.saveToPhotos(
      [message(.video(caption: nil))], library: FakePhotoLibrary(error: .saveFailed))
    #expect(viewModel.errorMessage == "Could not save to Photos.")
  }

  @Test func aFailedDownloadSavesNothing() async {
    let media = FakeMediaRepository()
    media.result = .failure(.downloadFailed)
    let library = FakePhotoLibrary()
    let viewModel = viewModel(media)
    await viewModel.saveToPhotos([message(.image(caption: nil))], library: library)
    #expect(library.added.isEmpty)
    #expect(viewModel.errorMessage == "Could not download the file.")
    #expect(viewModel.toast == nil)
  }

  @Test func theViewerSavesItsPicture() async {
    let media = FakeMediaRepository()
    let library = FakePhotoLibrary()
    let outcome = await SaveToPhotosOutcome.saving(picture: reference, from: media, to: library)
    #expect(outcome == .saved(count: 1))
    #expect(library.added == [[.picture(folder.appending(path: "image"))]])
    #expect(media.fileNames == ["image"])
  }

  @Test func theViewerReportsAFailedDownload() async {
    let media = FakeMediaRepository()
    media.result = .failure(.downloadFailed)
    let library = FakePhotoLibrary()
    let outcome = await SaveToPhotosOutcome.saving(picture: reference, from: media, to: library)
    #expect(outcome == .failed)
    #expect(!outcome.isSaved)
    #expect(library.added.isEmpty)
  }
}
