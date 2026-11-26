import DesignSystem
import Domain
import Foundation
import Observation
import SwiftUI

/// Makes a timeline of one kind of message of a room, for a chat details tab.
public typealias ContentTimeline = @MainActor (RoomContentKind) -> any TimelineRepository

/// The pictures the viewer opens on, and which one first.
struct OpenedPictures: Identifiable {
  let pictures: [MediaReference]
  let index: Int
  var id: Int { index }
}

/// One message on a chat details tab; on the Links tab, with the message's first link.
public struct RoomContentEntry: Identifiable, Equatable, Sendable {
  /// The timeline item's id.
  public let id: String
  public let message: TimelineMessage
  public let link: URL?
}

/// The entries of one month, as Photos and the Flutter tabs group them.
public struct RoomContentMonth: Identifiable, Equatable, Sendable {
  public let id: String
  public let title: String
  public let entries: [RoomContentEntry]
}

/// A chat details tab (Flutter `chat_details_tab_mixin`): the room's pictures and videos, files, or messages with a
/// link, newest first. It follows a timeline of only that kind of message and loads older pages while its end is on
/// screen, as a filtered page can hold none.
@MainActor @Observable
public final class RoomContentViewModel {
  public let kind: RoomContentKind
  /// Newest first.
  public private(set) var entries: [RoomContentEntry] = []
  public private(set) var reachedStart = false
  public private(set) var failed = false
  public private(set) var errorMessage: String?

  @ObservationIgnored private let repository: any TimelineRepository
  @ObservationIgnored let media: any MediaRepository
  @ObservationIgnored private var isOpen = false
  @ObservationIgnored private var isLoadingOlder = false

  public init(
    kind: RoomContentKind, repository: any TimelineRepository, media: any MediaRepository
  ) {
    self.kind = kind
    self.repository = repository
    self.media = media
  }

  /// Opens the messages of this kind and follows them until the calling task ends; then closes them.
  public func start() async {
    let items: AsyncStream<[TimelineItem]>
    do {
      items = try await repository.open()
    } catch {
      failed = true
      return
    }
    isOpen = true
    for await list in items {
      entries = Self.entries(in: list, kind: kind)
      if list.contains(where: { $0.kind == .timelineStart }) { reachedStart = true }
    }
    isOpen = false
    await repository.close()
  }

  /// Loads older pages until the start of the room, while the calling task runs (the end of the tab is on screen). A
  /// failed page waits longer before the next try.
  public func loadOlderWhileVisible() async {
    while !reachedStart, !Task.isCancelled {
      let loaded = await loadOlder()
      try? await Task.sleep(for: loaded ? .milliseconds(250) : .seconds(3))
    }
  }

  /// Loads one older page; `false` only when the page failed. Before the timeline is open, it does nothing.
  @discardableResult
  func loadOlder() async -> Bool {
    guard isOpen, !isLoadingOlder, !reachedStart else { return true }
    isLoadingOlder = true
    defer { isLoadingOlder = false }
    do {
      if try await repository.loadOlder() { reachedStart = true }
      return true
    } catch {
      return false
    }
  }

  /// The entries by month, newest first.
  public var months: [RoomContentMonth] {
    var months: [RoomContentMonth] = []
    let calendar = Calendar.current
    for entry in entries {
      let parts = calendar.dateComponents([.year, .month], from: entry.message.date)
      let id = "\(parts.year ?? 0)-\(parts.month ?? 0)"
      if let last = months.last, last.id == id {
        months[months.count - 1] = RoomContentMonth(
          id: id, title: last.title, entries: last.entries + [entry])
      } else {
        let title = entry.message.date.formatted(.dateTime.month(.wide).year())
        months.append(RoomContentMonth(id: id, title: title, entries: [entry]))
      }
    }
    return months
  }

  /// The pictures of the Media tab, for the full-screen viewer; videos play on their own.
  var pictures: [RoomContentEntry] {
    entries.filter { if case .image = $0.message.body { true } else { false } }
  }

  /// Downloads an entry's file; `nil`, with an error message, when it fails.
  func file(of entry: RoomContentEntry) async -> URL? {
    guard let reference = entry.message.media else { return nil }
    errorMessage = nil
    do {
      return try await media.file(reference, filename: RoomViewModel.fileName(of: entry.message))
    } catch {
      errorMessage = localized("Could not download the file.")
      return nil
    }
  }

  /// The messages of `kind` in a timeline, newest first, as the Flutter tabs pick them: pictures and videos with
  /// their media, files, and text with a web link.
  static func entries(in items: [TimelineItem], kind: RoomContentKind) -> [RoomContentEntry] {
    items.reversed().compactMap { item in
      guard case .message(let message) = item.kind else { return nil }
      switch (kind, message.body) {
      case (.media, .image), (.media, .video), (.files, .file):
        guard message.media != nil else { return nil }
        return RoomContentEntry(id: item.id, message: message, link: nil)
      case (.links, .text(let text)), (.links, .notice(let text)), (.links, .emote(let text)):
        return firstLink(in: text).map { RoomContentEntry(id: item.id, message: message, link: $0) }
      default:
        return nil
      }
    }
  }

  /// The first web link in a text (Flutter `firstValidUrl`), or `nil`.
  static func firstLink(in text: String) -> URL? {
    guard
      let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
    else { return nil }
    return detector.matches(in: text, range: NSRange(text.startIndex..., in: text))
      .lazy.compactMap(\.url)
      .first { ["http", "https"].contains($0.scheme?.lowercased() ?? "") }
  }
}

extension RoomContentKind {
  var title: String {
    switch self {
    case .media: localized("Media")
    case .files: localized("Files")
    case .links: localized("Links")
    case .text: localized("Messages")
    }
  }

  var systemImage: String {
    switch self {
    case .media: "photo.on.rectangle"
    case .files: "doc"
    case .links: "link"
    case .text: "text.bubble"
    }
  }

  var emptyText: String {
    switch self {
    case .media: localized("No pictures or videos")
    case .files: localized("No files")
    case .links: localized("No links")
    case .text: localized("No messages")
    }
  }
}

/// A chat details tab: pictures and videos in a square grid, as Photos shows them, files and links as a list; each
/// grouped by month. A picture opens full screen, a video plays, a file downloads to share, a link opens in Safari.
struct RoomContentScreen: View {
  /// Kept as state: the details page makes a new tab model each time it draws its destination.
  @State private var viewModel: RoomContentViewModel
  @State private var viewer: OpenedPictures?
  @State private var video: DownloadedFile?
  @State private var downloaded: DownloadedFile?
  @State private var downloading: String?
  @Environment(\.openURL) private var openURL

  init(viewModel: RoomContentViewModel) {
    _viewModel = State(initialValue: viewModel)
  }

  var body: some View {
    content
      .background(SysColors.background)
      .navigationTitle(viewModel.kind.title)
      .navigationBarTitleDisplayMode(.inline)
      .task { await viewModel.start() }
      .fullScreenCover(item: $viewer) { opened in
        ImageViewer(
          pictures: opened.pictures, startIndex: opened.index, repository: viewModel.media,
          title: viewModel.kind.title)
      }
      .fullScreenCover(item: $video) { file in VideoPlayerScreen(url: file.url) }
      .sheet(item: $downloaded) { file in ShareSheetLink(url: file.url) }
  }

  @ViewBuilder private var content: some View {
    if viewModel.failed {
      ContentUnavailableView(
        localized("Could not load this chat"), systemImage: "exclamationmark.triangle")
    } else if viewModel.entries.isEmpty, viewModel.reachedStart {
      ContentUnavailableView(viewModel.kind.emptyText, systemImage: viewModel.kind.systemImage)
    } else if viewModel.kind == .media {
      mediaGrid
    } else {
      list
    }
  }

  /// Keeps loading older pages while it is on screen.
  @ViewBuilder private var loadingMore: some View {
    if !viewModel.reachedStart {
      ProgressView()
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .task { await viewModel.loadOlderWhileVisible() }
    }
  }

  private var mediaGrid: some View {
    ScrollView {
      // Lazy, so the loader at the end only runs when the grid is scrolled near it.
      LazyVStack(spacing: 0) {
        LazyVGrid(
          columns: [GridItem(.adaptive(minimum: 96), spacing: 2)], spacing: 2,
          pinnedViews: [.sectionHeaders]
        ) {
          ForEach(viewModel.months) { month in
            Section {
              ForEach(month.entries) { entry in mediaCell(entry) }
            } header: {
              Text(month.title)
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.bar)
            }
          }
        }
        loadingMore
      }
    }
  }

  private func mediaCell(_ entry: RoomContentEntry) -> some View {
    Button {
      Task { await open(entry) }
    } label: {
      Color.clear
        .aspectRatio(1, contentMode: .fit)
        .overlay {
          if let reference = entry.message.media {
            RemoteImage(
              media: reference, size: CGSize(width: 160, height: 160), repository: viewModel.media)
          }
        }
        .clipped()
        .overlay(alignment: .bottomLeading) {
          if case .video = entry.message.body {
            Image(systemName: downloading == entry.id ? "hourglass" : "video.fill")
              .font(.caption)
              .foregroundStyle(.white)
              .shadow(radius: 2)
              .padding(6)
          }
        }
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(isVideo(entry) ? localized("Video") : localized("Picture"))
    .accessibilityValue(entry.message.date.formatted(date: .abbreviated, time: .shortened))
  }

  private var list: some View {
    List {
      ForEach(viewModel.months) { month in
        Section(month.title) {
          ForEach(month.entries) { entry in
            if viewModel.kind == .links { linkRow(entry) } else { fileRow(entry) }
          }
        }
      }
      if let message = viewModel.errorMessage {
        Text(message).foregroundStyle(SysColors.error)
      }
      loadingMore.listRowBackground(Color.clear)
    }
  }

  private func fileRow(_ entry: RoomContentEntry) -> some View {
    Button {
      Task { await open(entry) }
    } label: {
      HStack(spacing: 12) {
        ZStack {
          RoundedRectangle(cornerRadius: 8).fill(SysColors.primary.opacity(0.12))
          if downloading == entry.id {
            ProgressView()
          } else {
            Image(systemName: "doc.fill").foregroundStyle(SysColors.primary)
          }
        }
        .frame(width: 40, height: 40)
        VStack(alignment: .leading, spacing: 2) {
          Text(RoomViewModel.fileName(of: entry.message)).lineLimit(2)
          Text(detail(of: entry))
            .font(.footnote)
            .foregroundStyle(SysColors.textSecondary)
            .lineLimit(1)
        }
      }
    }
    .foregroundStyle(SysColors.onSurface)
    .disabled(downloading != nil)
  }

  private func linkRow(_ entry: RoomContentEntry) -> some View {
    Button {
      if let link = entry.link { openURL(link) }
    } label: {
      HStack(spacing: 12) {
        ZStack {
          RoundedRectangle(cornerRadius: 8).fill(SysColors.primary.opacity(0.12))
          Image(systemName: "link").foregroundStyle(SysColors.primary)
        }
        .frame(width: 40, height: 40)
        VStack(alignment: .leading, spacing: 2) {
          Text(entry.link?.host() ?? "").font(.headline).lineLimit(1)
          Text(entry.link?.absoluteString ?? "")
            .font(.subheadline)
            .foregroundStyle(SysColors.primary)
            .lineLimit(2)
          Text(detail(of: entry))
            .font(.footnote)
            .foregroundStyle(SysColors.textSecondary)
            .lineLimit(1)
        }
      }
    }
    .foregroundStyle(SysColors.onSurface)
    .contextMenu {
      if let link = entry.link {
        Button(localized("Copy link"), systemImage: "doc.on.doc") {
          UIPasteboard.general.url = link
        }
        ShareLink(item: link)
      }
    }
  }

  /// "Alice · 12 Nov" or, for a file, its size first.
  private func detail(of entry: RoomContentEntry) -> String {
    var parts: [String] = []
    if viewModel.kind == .files, let size = RoomViewModel.sizeText(entry.message.media?.size) {
      parts.append(size)
    }
    parts.append(entry.message.senderName)
    parts.append(entry.message.date.formatted(.dateTime.day().month(.abbreviated)))
    return parts.joined(separator: " · ")
  }

  private func isVideo(_ entry: RoomContentEntry) -> Bool {
    if case .video = entry.message.body { true } else { false }
  }

  private func open(_ entry: RoomContentEntry) async {
    switch entry.message.body {
    case .image:
      // The viewer gets the pictures loaded so far: older pages keep coming while it is open.
      let pictures = viewModel.pictures
      guard let index = pictures.firstIndex(where: { $0.id == entry.id }) else { return }
      viewer = OpenedPictures(pictures: pictures.compactMap(\.message.media), index: index)
    case .video, .file:
      guard downloading == nil else { return }
      downloading = entry.id
      defer { downloading = nil }
      guard let url = await viewModel.file(of: entry) else { return }
      if isVideo(entry) {
        video = DownloadedFile(url: url)
      } else {
        downloaded = DownloadedFile(url: url)
      }
    default:
      break
    }
  }
}
