import Domain
import Foundation
import Observation

extension RoomViewModel {
  func loadGifsAvailability() async {
    let enabled = await repository.gifsEnabled()
    gifsOff = !enabled
    guard let gifs, enabled else {
      gifsAvailable = false
      return
    }
    gifsAvailable = await gifs.searchPlaceholder() != nil
  }

  func gifsChanged(enabled: Bool) async {
    gifsOff = !enabled
    guard enabled, let gifs else {
      gifsAvailable = false
      return
    }
    gifsAvailable = await gifs.searchPlaceholder() != nil
  }

  static func isHiddenGif(_ message: TimelineMessage, gifsOff: Bool) -> Bool {
    guard gifsOff, case .image = message.body else { return false }
    return message.media?.mimeType?.lowercased() == "image/gif"
  }

  func makeGifPicker() -> GifPicker? {
    guard gifsAvailable, let gifs else { return nil }
    return GifPicker(repository: gifs, locale: Self.gifLocale())
  }

  static func gifLocale(_ locale: Locale = .current) -> String {
    locale.language.languageCode?.identifier ?? "en"
  }

  public func send(gif: Gif) async {
    guard let gifs else { return }
    errorMessage = nil
    uploadCount += 1
    let file: GifFile
    do {
      file = try await gifs.download(gif)
    } catch {
      uploadCount -= 1
      errorMessage =
        error == .expired
        ? "This GIF is no longer available. Search again."
        : "Could not download the GIF. Please try again."
      return
    }
    uploadCount -= 1
    let width = gif.width > 0 ? gif.width : nil
    let height = gif.height > 0 ? gif.height : nil
    await send(
      attachment: .image(width: width, height: height), fileURL: file.fileURL,
      mimeType: file.mimeType, size: file.size)
    try? FileManager.default.removeItem(at: file.fileURL.deletingLastPathComponent())
  }
}

@MainActor @Observable
final class GifPicker {
  enum Phase: Equatable {
    case loading
    case loaded
    case failed
  }

  private(set) var placeholder = ""
  private(set) var gifs: [Gif] = []
  private(set) var phase = Phase.loading
  private(set) var next: String?
  private(set) var isLoadingMore = false
  var query = "" {
    didSet {
      guard query != oldValue else { return }
      scheduleSearch()
    }
  }

  @ObservationIgnored private let repository: any GifRepository
  @ObservationIgnored private let locale: String
  @ObservationIgnored var searchDelay: Duration = .milliseconds(300)
  @ObservationIgnored private var searchTask: Task<Void, Never>?
  @ObservationIgnored private var shownSearch = ""

  init(repository: any GifRepository, locale: String) {
    self.repository = repository
    self.locale = locale
  }

  func start() async {
    placeholder = await repository.searchPlaceholder() ?? ""
    await load(search: query.trimmingCharacters(in: .whitespacesAndNewlines))
  }

  var isEmpty: Bool { phase == .loaded && gifs.isEmpty }

  func loadMore() async {
    guard let cursor = next, !isLoadingMore else { return }
    isLoadingMore = true
    defer { isLoadingMore = false }
    let search = shownSearch
    guard let page = await fetch(search: search, cursor: cursor), search == shownSearch else {
      return
    }
    let known = Set(gifs.map(\.id))
    gifs += page.results.filter { !known.contains($0.id) }
    next = page.next
  }

  private func scheduleSearch() {
    searchTask?.cancel()
    let delay = searchDelay
    searchTask = Task { [weak self] in
      try? await Task.sleep(for: delay)
      guard !Task.isCancelled, let self else { return }
      await self.load(search: self.query.trimmingCharacters(in: .whitespacesAndNewlines))
    }
  }

  private func load(search: String) async {
    if gifs.isEmpty { phase = .loading }
    shownSearch = search
    let page = await fetch(search: search, cursor: nil)
    guard search == shownSearch else { return }
    guard let page else {
      phase = .failed
      return
    }
    gifs = page.results
    next = page.next
    phase = .loaded
  }

  private func fetch(search: String, cursor: String?) async -> GifPage? {
    search.isEmpty
      ? await repository.trending(cursor: cursor, locale: locale)
      : await repository.search(search, cursor: cursor, locale: locale)
  }
}
