import DesignSystem
import Domain
import QuickLook
import SwiftUI

/// The media of a message inside its bubble, as the Flutter chat shows it: pictures, videos and stickers as a
/// thumbnail at their aspect ratio (a tap opens a picture full screen), voice messages and files as a row with the name
/// and size (a tap downloads the file and offers to open or share it).
struct MessageMediaView: View {
  let message: TimelineMessage
  let media: MediaReference
  let width: CGFloat
  let viewModel: RoomViewModel

  @State private var isViewerShown = false
  @State private var downloaded: DownloadedFile?
  @State private var isDownloading = false
  @State private var video: DownloadedFile?
  /// A downloaded file shown in Quick Look (PDF, documents, pictures), which also offers Share and Save to Files.
  @State private var previewURL: URL?

  var body: some View {
    switch message.body {
    case .image, .sticker, .video:
      thumbnail
    case .audio:
      AudioMessageRow(message: message, viewModel: viewModel)
    default:
      fileRow
    }
  }

  /// `MessageStyle` caps a picture at the bubble width and 300 pt tall; without a size it is square.
  private var thumbnailSize: CGSize {
    let ratio = media.aspectRatio ?? 1
    let height = min(300, width * ratio)
    return CGSize(width: min(width, height / ratio), height: height)
  }

  /// The user's own picture, sent in the last minutes. The SDK keeps what it uploaded, so the picture shows from that
  /// copy at once; the server's thumbnail of a new upload took over a minute on a slow server, with a blank tile.
  static func accessibilityLabel(of body: TimelineMessage.Body) -> String {
    switch body {
    case .image(let caption?) where !caption.trimmingCharacters(in: .whitespaces).isEmpty:
      caption
    case .video(let caption?) where !caption.trimmingCharacters(in: .whitespaces).isEmpty:
      "Video: \(caption)"
    case .video: "Video"
    case .sticker(let text): "Sticker \(text)"
    default: "Picture"
    }
  }

  static func wasJustSent(_ message: TimelineMessage, now: Date = Date()) -> Bool {
    guard message.isOwn, case .image = message.body else { return false }
    return now.timeIntervalSince(message.date) < 600
  }

  /// A button rather than a tap gesture, so a long press still reaches the bubble's message menu.
  private var thumbnail: some View {
    let size = thumbnailSize
    return Button {
      // The finger lifting after a long press must not open the picture under the actions layer.
      guard viewModel.focus == nil else { return }
      if case .video = message.body {
        Task { await playVideo() }
      } else {
        isViewerShown = true
      }
    } label: {
      RemoteImage(
        media: media, size: size, repository: viewModel.media,
        prefersOriginal: Self.wasJustSent(message)
      )
      .frame(width: size.width, height: size.height)
      .clipShape(.rect(cornerRadius: 12))
      .overlay {
        if message.sendState == .sending {
          UploadProgressRing(progress: message.uploadProgress)
        } else if case .video = message.body {
          if isDownloading {
            ProgressView().tint(.white).controlSize(.large)
          } else {
            Image(systemName: "play.circle.fill")
              .font(.system(size: 44))
              .foregroundStyle(.white.opacity(0.9))
          }
        }
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(Self.accessibilityLabel(of: message.body))
    .fullScreenCover(item: $video) { file in VideoPlayerScreen(url: file.url) }
    .fullScreenCover(isPresented: $isViewerShown) {
      ImageViewer(
        pictures: [media], startIndex: 0, repository: viewModel.media, title: message.senderName)
    }
    .sheet(item: $downloaded) { file in ShareSheetLink(url: file.url) }
  }

  private var isAudio: Bool {
    if case .audio = message.body { true } else { false }
  }

  private var fileRow: some View {
    Button {
      guard viewModel.focus == nil else { return }
      Task { await download() }
    } label: {
      HStack(spacing: 12) {
        ZStack {
          Circle().fill(SysColors.primary).frame(width: 40, height: 40)
          if message.sendState == .sending {
            UploadProgressRing(progress: message.uploadProgress, diameter: 30, lineWidth: 3)
          } else if isDownloading {
            ProgressView().tint(.white)
          } else {
            Image(systemName: isAudio ? "waveform" : "doc.fill")
              .foregroundStyle(.white)
          }
        }
        VStack(alignment: .leading, spacing: 2) {
          Text(RoomViewModel.fileName(of: message))
            .textStyle(TextStyles.bodyMedium)
            .foregroundStyle(SysColors.onSurface)
            .lineLimit(2)
          if let size = RoomViewModel.sizeText(media.size) {
            Text(size).textStyle(TextStyles.labelSmall).foregroundStyle(SysColors.textSecondary)
          }
        }
      }
    }
    .buttonStyle(.plain)
    .disabled(isDownloading)
    .quickLookPreview($previewURL)
    .sheet(item: $downloaded) { file in ShareSheetLink(url: file.url) }
  }

  private func playVideo() async {
    guard !isDownloading else { return }
    isDownloading = true
    defer { isDownloading = false }
    video = await viewModel.file(of: message).map(DownloadedFile.init(url:))
  }

  /// Downloads the file, then shows it in Quick Look when it can, or offers to share it otherwise.
  private func download() async {
    guard !isDownloading else { return }
    isDownloading = true
    defer { isDownloading = false }
    guard let url = await viewModel.file(of: message) else { return }
    if QLPreviewController.canPreview(url as NSURL) {
      previewURL = url
    } else {
      downloaded = DownloadedFile(url: url)
    }
  }
}

/// How much of a sending picture, video or file is uploaded: a ring that fills smoothly over a dimmed disc, or a
/// spinning arc before the first progress arrives.
struct UploadProgressRing: View {
  let progress: Double?
  var diameter: CGFloat = 48
  var lineWidth: CGFloat = 4

  @State private var spins = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    ZStack {
      Circle().fill(.black.opacity(0.35))
      Circle().stroke(.white.opacity(0.3), lineWidth: lineWidth).padding(lineWidth)
      Circle()
        .trim(from: 0, to: progress.map { max(0.03, $0) } ?? 0.25)
        .stroke(.white, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
        .rotationEffect(.degrees(progress == nil && spins ? 270 : -90))
        .padding(lineWidth)
        .animation(.easeOut(duration: 0.25), value: progress)
        .animation(
          progress == nil ? .linear(duration: 1).repeatForever(autoreverses: false) : .default,
          value: spins)
    }
    .frame(width: diameter, height: diameter)
    .onAppear { spins = !reduceMotion }
    .transition(.scale.combined(with: .opacity))
    .accessibilityElement()
    .accessibilityLabel("Uploading")
    .accessibilityValue(progress.map { "\(Int($0 * 100)) percent" } ?? "")
  }
}

/// A downloaded file, as the sheet that offers it needs it.
struct DownloadedFile: Identifiable {
  let url: URL
  var id: URL { url }
}

/// Files downloaded for the share sheet: one, or every picture of an album.
struct DownloadedFiles: Identifiable {
  let urls: [URL]
  let id = UUID()
}

/// A sheet that offers to open or share downloaded files.
struct ShareSheetLink: View {
  let urls: [URL]

  init(url: URL) { urls = [url] }
  init(urls: [URL]) { self.urls = urls }

  var body: some View {
    VStack(spacing: 16) {
      Image(systemName: urls.count > 1 ? "doc.on.doc.fill" : "doc.fill")
        .font(.system(size: 44)).foregroundStyle(SysColors.primary)
      Text(urls.count == 1 ? urls[0].lastPathComponent : "\(urls.count) files")
        .textStyle(TextStyles.titleMedium).multilineTextAlignment(.center)
      ShareLink(items: urls) {
        Label("Share", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
      }
      .buttonStyle(.twakePrimary)
    }
    .padding(24)
    .presentationDetents([.medium])
  }
}

/// A thumbnail loaded from the media repository; a neutral box with an icon while it loads or when it fails.
struct RemoteImage: View {
  let media: MediaReference
  let size: CGSize
  let repository: any MediaRepository
  /// Loads the whole file first (kept on the device for a picture just sent), scaled down to `size`, and falls back
  /// to the thumbnail.
  var prefersOriginal = false

  @State private var image: UIImage?
  @State private var failed = false
  @State private var placeholder: UIImage?
  @Environment(\.displayScale) private var scale

  var body: some View {
    ZStack {
      if let image {
        Image(uiImage: image).resizable().scaledToFill()
          .transition(.opacity)
      } else {
        if let placeholder {
          // The sender's blurred colours hold the place while the picture loads.
          Image(uiImage: placeholder).resizable().scaledToFill()
        } else {
          Rectangle().fill(SysColors.surface)
        }
        if failed {
          Image(systemName: "photo").foregroundStyle(SysColors.textSecondary)
        } else {
          ProgressView()
        }
      }
    }
    .task(id: media.source) {
      if image == nil { placeholder = media.blurhash.flatMap { BlurHashImage.image(from: $0) } }
      let pixels = CGSize(width: size.width * scale, height: size.height * scale)
      if prefersOriginal, let data = try? await repository.content(media),
        let original = UIImage(data: data)
      {
        let scaled = await original.byPreparingThumbnail(ofSize: Self.fill(original.size, pixels))
        withAnimation(.easeIn(duration: 0.25)) { image = scaled ?? original }
        failed = false
        return
      }
      do {
        let data = try await repository.thumbnail(
          media, width: Int(pixels.width), height: Int(pixels.height))
        withAnimation(.easeIn(duration: 0.25)) { image = UIImage(data: data) }
        failed = image == nil
      } catch {
        failed = true
      }
    }
  }
}

extension RemoteImage {
  /// The size that keeps `original`'s shape and covers `target`, never larger than the original.
  static func fill(_ original: CGSize, _ target: CGSize) -> CGSize {
    guard original.width > 0, original.height > 0 else { return target }
    let ratio = min(1, max(target.width / original.width, target.height / original.height))
    return CGSize(width: original.width * ratio, height: original.height * ratio)
  }
}

/// Pictures full screen, as the Flutter image viewer: swipe between the pictures of an album, pinch or double-tap to
/// zoom, Close, Share and Save to Photos. They are toolbar buttons, so iOS places them: Close in the navigation bar,
/// Share and Save in the bottom bar on a phone, all in the side rail on the unfolded Duo, as Photos does.
struct ImageViewer: View {
  let pictures: [MediaReference]
  let repository: any MediaRepository
  let title: String
  let library: any PhotoLibrarySaving

  let startIndex: Int

  @Environment(\.dismiss) private var dismiss
  @State private var index: Int?
  @State private var images: [Int: UIImage] = [:]
  @State private var isSaving = false
  /// What the last Save to Photos did, shown as a toast for two seconds.
  @State private var saveOutcome: SaveToPhotosOutcome?

  init(
    pictures: [MediaReference], startIndex: Int, repository: any MediaRepository, title: String,
    library: any PhotoLibrarySaving = SystemPhotoLibrary()
  ) {
    self.pictures = pictures
    self.repository = repository
    self.title = title
    self.library = library
    self.startIndex = startIndex
    // The scroll view reads its first page from here; set later, in `onAppear`, a long list of lazy pages could land
    // on another one.
    _index = State(initialValue: startIndex)
  }

  private var currentIndex: Int { index ?? startIndex }

  var body: some View {
    NavigationStack {
      // A paged scroll view, not a TabView: a paged TabView ignores the page it is first given.
      ScrollView(.horizontal) {
        LazyHStack(spacing: 0) {
          ForEach(pictures.indices, id: \.self) { position in
            ZoomablePicture(media: pictures[position], repository: repository) {
              images[position] = $0
            }
            .containerRelativeFrame([.horizontal, .vertical])
            .id(position)
          }
        }
        .scrollTargetLayout()
      }
      .scrollTargetBehavior(.paging)
      .scrollIndicators(.hidden)
      .scrollPosition(id: $index)
      // The next picture must not show through the Duo's side status area.
      .clipped()
      .background(Color.black.ignoresSafeArea())
      .navigationTitle(pictures.count > 1 ? "\(currentIndex + 1) / \(pictures.count)" : title)
      .navigationBarTitleDisplayMode(.inline)
      .toolbarBackground(.black, for: .navigationBar)
      .toolbarColorScheme(.dark, for: .navigationBar)
      .toolbarBackground(.black, for: .bottomBar)
      .toolbarColorScheme(.dark, for: .bottomBar)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button("Close", systemImage: "xmark") { dismiss() }
        }
        if let image = images[currentIndex] {
          ToolbarItem(placement: .bottomBar) {
            ShareLink(
              item: Image(uiImage: image),
              preview: SharePreview(title, image: Image(uiImage: image))
            ) {
              Image(systemName: "square.and.arrow.up")
            }
            .accessibilityLabel("Share")
          }
          ToolbarItem(placement: .bottomBar) {
            Button("Save to Photos", systemImage: "square.and.arrow.down") {
              Task { await save(pictures[currentIndex]) }
            }
            .disabled(isSaving)
          }
        }
      }
    }
    .overlay(alignment: .top) {
      if let saveOutcome {
        Toast(
          text: saveOutcome.text,
          systemImage: saveOutcome.isSaved ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
        )
      }
    }
    .animation(.spring(response: 0.4, dampingFraction: 0.8), value: saveOutcome)
    .sensoryFeedback(trigger: saveOutcome) { _, new in
      guard let new else { return nil }
      return new.isSaved ? .success : .error
    }
    .task(id: saveOutcome) {
      guard saveOutcome != nil else { return }
      try? await Task.sleep(for: .seconds(2))
      if !Task.isCancelled { saveOutcome = nil }
    }
  }

  private func save(_ picture: MediaReference) async {
    guard !isSaving else { return }
    isSaving = true
    defer { isSaving = false }
    saveOutcome = await .saving(picture: picture, from: repository, to: library)
  }
}

/// One picture of the viewer: it loads, fades in, and zooms with a pinch or a double tap.
struct ZoomablePicture: View {
  let media: MediaReference
  let repository: any MediaRepository
  let onLoad: (UIImage) -> Void

  @State private var image: UIImage?
  @State private var failed = false
  @State private var zoom: CGFloat = 1
  @State private var lastZoom: CGFloat = 1

  var body: some View {
    ZStack {
      if let image {
        Image(uiImage: image)
          .resizable()
          .scaledToFit()
          .scaleEffect(zoom)
          .gesture(
            MagnifyGesture()
              .onChanged { zoom = max(1, lastZoom * $0.magnification) }
              .onEnded { _ in
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { zoom = min(zoom, 4) }
                lastZoom = zoom
              }
          )
          .onTapGesture(count: 2) {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
              zoom = zoom > 1 ? 1 : 2.5
            }
            lastZoom = zoom
          }
          .transition(.opacity.combined(with: .scale(scale: 0.96)))
      } else if failed {
        Label("Could not load the picture.", systemImage: "photo").foregroundStyle(.white)
      } else {
        ProgressView().tint(.white)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .task(id: media.source) {
      do {
        let loaded = UIImage(data: try await repository.content(media))
        withAnimation(.easeOut(duration: 0.25)) { image = loaded }
        failed = loaded == nil
        if let loaded { onLoad(loaded) }
      } catch {
        failed = true
      }
    }
  }
}

/// Pictures sent together, as one album (Flutter `images_builder`, Telegram albums): two side by side, three as one
/// wide and two below, four or more in a two-column grid, at most six cells with "+N" on the last. A tap opens the
/// viewer on that picture.
struct AlbumGrid: View {
  let album: AlbumRowModel
  let width: CGFloat
  let viewModel: RoomViewModel

  @State private var viewerStart: ViewerStart?

  private static let spacing: CGFloat = 2
  private static let maxCells = 6

  private var pictures: [MediaReference] { album.messages.compactMap(\.media) }

  var body: some View {
    let cells = Array(pictures.prefix(Self.maxCells).enumerated())
    let half = (width - Self.spacing) / 2
    VStack(spacing: Self.spacing) {
      if cells.count == 3 {
        cell(cells[0], width: width, height: half)
        HStack(spacing: Self.spacing) {
          cell(cells[1], width: half, height: half)
          cell(cells[2], width: half, height: half)
        }
      } else {
        ForEach(Array(stride(from: 0, to: cells.count, by: 2)), id: \.self) { row in
          HStack(spacing: Self.spacing) {
            cell(cells[row], width: row + 1 < cells.count ? half : width, height: half)
            if row + 1 < cells.count { cell(cells[row + 1], width: half, height: half) }
          }
        }
      }
    }
    .clipShape(.rect(cornerRadius: 12))
    .fullScreenCover(item: $viewerStart) { start in
      ImageViewer(
        pictures: pictures, startIndex: start.index, repository: viewModel.media,
        title: album.messages.first?.senderName ?? "")
    }
  }

  private func cell(
    _ entry: (offset: Int, element: MediaReference), width: CGFloat, height: CGFloat
  ) -> some View {
    Button {
      guard viewModel.focus == nil else { return }
      viewerStart = ViewerStart(index: entry.offset)
    } label: {
      cellImage(entry, width: width, height: height)
    }
    .buttonStyle(.plain)
  }

  private func cellImage(
    _ entry: (offset: Int, element: MediaReference), width: CGFloat, height: CGFloat
  ) -> some View {
    RemoteImage(
      media: entry.element, size: CGSize(width: width, height: height), repository: viewModel.media
    )
    .frame(width: width, height: height)
    .clipped()
    .overlay {
      let hidden = pictures.count - Self.maxCells
      if entry.offset == Self.maxCells - 1, hidden > 0 {
        ZStack {
          Color.black.opacity(0.45)
          Text("+\(hidden)").textStyle(TextStyles.headlineSmall).foregroundStyle(.white)
        }
      }
    }
    .contentShape(Rectangle())
  }
}

/// Which picture of an album the viewer opens on.
struct ViewerStart: Identifiable {
  let index: Int
  var id: Int { index }
}
