import AVFoundation
import DesignSystem
import Domain
import Foundation
import ImageIO
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// Turns what the pickers return into files the upload can read: pictures and videos from the photo library, and
/// documents from the Files app (iCloud Drive, Google Drive, Twake Drive or any other file provider). Each is copied into
/// a temporary folder of the app, so the upload never reads a security-scoped or remote URL.
enum AttachmentLoader {
  struct Loaded: Identifiable {
    let id = UUID()
    let kind: OutgoingAttachment.Kind
    let fileURL: URL
    let mimeType: String?
    let size: Int?
  }

  /// A picture or a video from the photo library, typed by its bytes rather than by the first type the picker lists.
  static func load(_ item: PhotosPickerItem) async -> Loaded? {
    guard let data = try? await item.loadTransferable(type: Data.self) else { return nil }
    let type = AttachmentType.of(data: data, offered: item.supportedContentTypes)
    let isVideo = type.conforms(to: .movie)
    let url = temporaryFile(
      named: "\(UUID().uuidString).\(type.preferredFilenameExtension ?? (isVideo ? "mov" : "jpg"))")
    guard (try? data.write(to: url)) != nil else { return nil }
    if isVideo {
      return Loaded(
        kind: .video(width: nil, height: nil, duration: nil), fileURL: url,
        mimeType: type.preferredMIMEType,
        size: data.count)
    }
    let image = UIImage(data: data)
    return Loaded(
      kind: .image(
        width: image.map { Int($0.size.width * $0.scale) },
        height: image.map { Int($0.size.height * $0.scale) }),
      fileURL: url, mimeType: type.preferredMIMEType ?? "image/jpeg", size: data.count)
  }

  /// A document the Files app gave, opened with its security scope and copied under its own name.
  static func load(document url: URL) -> Loaded? {
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    let copy = temporaryFile(named: url.lastPathComponent)
    guard (try? FileManager.default.copyItem(at: url, to: copy)) != nil else { return nil }
    let type = AttachmentType.of(file: url)
    let size = (try? copy.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
    return Loaded(
      kind: AttachmentType.kind(of: type), fileURL: copy, mimeType: type?.preferredMIMEType,
      size: size)
  }

  /// A picture from the clipboard, written to a temporary JPEG file like a picked one.
  static func load(image: UIImage) -> Loaded? {
    guard let data = image.jpegData(compressionQuality: 0.9) else { return nil }
    let url = temporaryFile(named: "\(UUID().uuidString).jpg")
    guard (try? data.write(to: url)) != nil else { return nil }
    return Loaded(
      kind: .image(
        width: Int(image.size.width * image.scale), height: Int(image.size.height * image.scale)),
      fileURL: url, mimeType: "image/jpeg", size: data.count)
  }

  /// A picture or a video the camera took, written to a temporary file like a picked one.
  static func load(camera info: [UIImagePickerController.InfoKey: Any]) -> Loaded? {
    if let movie = info[.mediaURL] as? URL {
      return load(document: movie)
    }
    guard let image = (info[.editedImage] ?? info[.originalImage]) as? UIImage,
      let data = image.jpegData(compressionQuality: 0.85)
    else { return nil }
    let url = temporaryFile(named: "\(UUID().uuidString).jpg")
    guard (try? data.write(to: url)) != nil else { return nil }
    return Loaded(
      kind: .image(
        width: Int(image.size.width * image.scale), height: Int(image.size.height * image.scale)),
      fileURL: url, mimeType: "image/jpeg", size: data.count)
  }

  /// Removes a copied file once it is uploaded.
  static func remove(_ loaded: Loaded) {
    try? FileManager.default.removeItem(at: loaded.fileURL.deletingLastPathComponent())
  }

  private static func temporaryFile(named name: String) -> URL {
    let folder = FileManager.default.temporaryDirectory.appending(
      path: "outgoing/\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder.appending(path: name.isEmpty ? "file" : name)
  }
}

/// The type of a picked file, from which its MIME type, extension and kind of message follow.
enum AttachmentType {
  /// What picked bytes are: the first listed type that is a picture or a video, else the first listed type, else
  /// JPEG; for a picture, the format its bytes hold wins (the picker may list a type it did not hand over). A video's
  /// bytes are not read: ImageIO may take a video's container for a HEIF picture.
  static func of(data: Data, offered: [UTType]) -> UTType {
    let listed =
      offered.first { $0.conforms(to: .image) || $0.conforms(to: .movie) } ?? offered.first
      ?? .jpeg
    guard !listed.conforms(to: .movie),
      let source = CGImageSourceCreateWithData(data as CFData, nil),
      let identifier = CGImageSourceGetType(source) as String?,
      let type = UTType(identifier)
    else { return listed }
    return type
  }

  /// A file's type as the file system records it, else as its extension says.
  static func of(file url: URL) -> UTType? {
    (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType
      ?? UTType(filenameExtension: url.pathExtension)
  }

  /// The message a file of this type is sent as.
  static func kind(of type: UTType?) -> OutgoingAttachment.Kind {
    guard let type else { return .file }
    if type.conforms(to: .image) { return .image(width: nil, height: nil) }
    if type.conforms(to: .movie) { return .video(width: nil, height: nil, duration: nil) }
    if type.conforms(to: .audio) { return .audio(duration: nil) }
    return .file
  }
}

/// The "+" of the Flutter composer (`chat_actions.dart` `PickerType`): Gallery and Documents. Each picked item is sent
/// on its own, so several pictures arrive together and show as an album.
struct AttachmentButton: View {
  let viewModel: RoomViewModel

  @State private var isGalleryShown = false
  @State private var isDocumentPickerShown = false
  @State private var pickedPhotos: [PhotosPickerItem] = []
  /// What was picked, shown before sending.
  @State private var preview: PickedBatch?
  @State private var isPollShown = false
  @State private var isCameraShown = false
  @State private var gifPicker: GifPicker?
  @State private var isStickerPickerShown = false
  @State private var drivePicker: DrivePicker?
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    Menu {
      if CameraPicker.isAvailable {
        Button("Camera", systemImage: "camera") { isCameraShown = true }
      }
      Button("Gallery", systemImage: "photo.on.rectangle") { isGalleryShown = true }
      Button("Documents", systemImage: "paperclip") { isDocumentPickerShown = true }
      if viewModel.driveAvailable {
        Button("Add from Drive", systemImage: "externaldrive") {
          Task { drivePicker = await viewModel.openDrive(isDark: colorScheme == .dark) }
        }
        .disabled(viewModel.isOpeningDrive)
        .accessibilityIdentifier(A11yIdentifiers.room.addFromDrive)
      }
      Button("Poll", systemImage: "chart.bar.xaxis") { isPollShown = true }
      if viewModel.gifsAvailable {
        Button("GIF", systemImage: "photo.stack") { gifPicker = viewModel.makeGifPicker() }
      }
      if !viewModel.stickerPacks.isEmpty {
        Button("Sticker", systemImage: "face.smiling") { isStickerPickerShown = true }
      }
      if UIPasteboard.general.hasImages {
        Button("Paste Picture", systemImage: "doc.on.clipboard") {
          let loaded = UIPasteboard.general.images?.compactMap(AttachmentLoader.load(image:)) ?? []
          if !loaded.isEmpty { preview = PickedBatch(items: loaded) }
        }
        .accessibilityIdentifier(A11yIdentifiers.room.pastePicture)
      }
    } label: {
      Image(systemName: "plus")
        .font(.system(size: 20, weight: .semibold))
        .foregroundStyle(SysColors.primary)
        .frame(width: 40, height: 40)
        .background(SysColors.surface, in: Circle())
    }
    .accessibilityLabel("Attach")
    .accessibilityIdentifier(A11yIdentifiers.room.attach)
    .photosPicker(
      isPresented: $isGalleryShown, selection: $pickedPhotos, maxSelectionCount: 10,
      matching: .any(of: [.images, .videos])
    )
    .onChange(of: pickedPhotos) { _, items in
      guard !items.isEmpty else { return }
      pickedPhotos = []
      Task {
        var loaded: [AttachmentLoader.Loaded] = []
        for item in items {
          if let one = await AttachmentLoader.load(item) { loaded.append(one) }
        }
        if !loaded.isEmpty { preview = PickedBatch(items: loaded) }
      }
    }
    .fileImporter(
      isPresented: $isDocumentPickerShown, allowedContentTypes: [.item],
      allowsMultipleSelection: true
    ) {
      result in
      guard case .success(let urls) = result else { return }
      let loaded = urls.compactMap(AttachmentLoader.load(document:))
      if !loaded.isEmpty { preview = PickedBatch(items: loaded) }
    }
    .sheet(item: $preview) { batch in
      SendPreviewSheet(items: batch.items, viewModel: viewModel)
    }
    .sheet(isPresented: $isPollShown) {
      CreatePollSheet(viewModel: viewModel)
    }
    .sheet(isPresented: $isStickerPickerShown) {
      StickerPickerSheet(packs: viewModel.stickerPacks, repository: viewModel.media) { sticker in
        Task { await viewModel.send(sticker: sticker) }
      }
    }
    .sheet(item: $gifPicker) { picker in
      GifPickerSheet(picker: picker) { gif in
        Task { await viewModel.send(gif: gif) }
      }
    }
    .fullScreenCover(item: $drivePicker) { picker in
      DrivePickerScreen(picker: picker) { outcome in
        guard drivePicker?.id == picker.id else { return }
        drivePicker = nil
        Task { await viewModel.finishDrivePick(outcome) }
      }
    }
    .fullScreenCover(isPresented: $isCameraShown) {
      CameraPicker { loaded in
        isCameraShown = false
        if let loaded { preview = PickedBatch(items: [loaded]) }
      }
      .ignoresSafeArea()
    }
  }
}

/// The system camera, for a picture or a video; it hands back the taken file, or `nil` when cancelled.
struct CameraPicker: UIViewControllerRepresentable {
  let onFinish: (AttachmentLoader.Loaded?) -> Void

  static var isAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

  func makeUIViewController(context: Context) -> UIImagePickerController {
    let picker = UIImagePickerController()
    picker.sourceType = .camera
    picker.mediaTypes =
      UIImagePickerController.availableMediaTypes(for: .camera) ?? ["public.image"]
    picker.videoQuality = .typeHigh
    picker.delegate = context.coordinator
    return picker
  }

  func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

  func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

  final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate
  {
    let onFinish: (AttachmentLoader.Loaded?) -> Void
    init(onFinish: @escaping (AttachmentLoader.Loaded?) -> Void) { self.onFinish = onFinish }

    func imagePickerController(
      _ picker: UIImagePickerController,
      didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
    ) {
      onFinish(AttachmentLoader.load(camera: info))
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { onFinish(nil) }
  }
}

/// The items one pick returned, shown in the preview.
struct PickedBatch: Identifiable {
  let id = UUID()
  let items: [AttachmentLoader.Loaded]
}

/// What is about to be sent (Flutter `send_media_native_dialog`): pictures and videos large, files as rows, each
/// removable, and one caption for the batch, prefilled with the composer's draft. Cancel deletes the copies and
/// sends nothing.
struct SendPreviewSheet: View {
  let viewModel: RoomViewModel
  @State private var items: [AttachmentLoader.Loaded]
  @State private var caption: String
  @State private var page: UUID?
  @State private var descriptions: [UUID: String] = [:]
  @State private var describing: UUID?
  @State private var descriptionText = ""
  @Environment(\.dismiss) private var dismiss
  @FocusState private var isCaptionFocused: Bool

  init(items: [AttachmentLoader.Loaded], viewModel: RoomViewModel) {
    self.viewModel = viewModel
    _items = State(initialValue: items)
    _caption = State(initialValue: viewModel.draft)
  }

  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        if items.allSatisfy(\.isVisual) {
          pictures
        } else {
          files
        }
        captionBar
      }
      .background(SysColors.background)
      .navigationTitle(title)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") {
            items.forEach(AttachmentLoader.remove)
            dismiss()
          }
        }
      }
    }
    .presentationDetents(items.allSatisfy(\.isVisual) ? [.large] : [.medium, .large])
    .interactiveDismissDisabled()
    .alert(
      "Describe this picture",
      isPresented: Binding(get: { describing != nil }, set: { if !$0 { describing = nil } })
    ) {
      TextField("Description", text: $descriptionText, axis: .vertical)
      Button("Cancel", role: .cancel) {}
      Button("Save") {
        if let id = describing { descriptions[id] = descriptionText }
      }
    } message: {
      Text("People who use a screen reader hear it. It is sent as the picture's caption.")
    }
  }

  private func describeButton(_ item: AttachmentLoader.Loaded) -> some View {
    let isDescribed = !(descriptions[item.id] ?? "").trimmingCharacters(in: .whitespaces).isEmpty
    return Button {
      descriptionText = descriptions[item.id] ?? ""
      describing = item.id
    } label: {
      Label("ALT", systemImage: isDescribed ? "checkmark" : "text.below.photo")
        .font(.caption.weight(.bold))
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.black.opacity(0.6), in: Capsule())
    }
    .accessibilityLabel(isDescribed ? "Edit the description" : "Add a description")
    .padding(12)
  }

  private var title: String {
    let count = items.count
    if items.allSatisfy(\.isVisual) {
      return count == 1 ? "1 item" : "\(count) items"
    }
    return count == 1 ? "1 file" : "\(count) files"
  }

  /// Pictures and videos, one per page, with the others as a strip of thumbnails to jump to or remove.
  private var pictures: some View {
    VStack(spacing: 12) {
      ScrollView(.horizontal) {
        LazyHStack(spacing: 0) {
          ForEach(items) { item in
            LocalPreview(item: item)
              .overlay(alignment: .bottomLeading) {
                if case .image = item.kind { describeButton(item) }
              }
              .containerRelativeFrame([.horizontal, .vertical])
              .id(item.id)
          }
        }
        .scrollTargetLayout()
      }
      .scrollTargetBehavior(.paging)
      .scrollIndicators(.hidden)
      .scrollPosition(id: $page)
      if items.count > 1 {
        ScrollView(.horizontal) {
          HStack(spacing: 8) {
            ForEach(items) { item in
              Button {
                withAnimation { page = item.id }
              } label: {
                LocalPreview(item: item)
                  .frame(width: 56, height: 56)
                  .clipShape(.rect(cornerRadius: 8))
                  .overlay {
                    RoundedRectangle(cornerRadius: 8)
                      .stroke(SysColors.primary, lineWidth: page == item.id ? 2 : 0)
                  }
              }
              .buttonStyle(.plain)
              .overlay(alignment: .topTrailing) { removeButton(item).offset(x: 6, y: -6) }
            }
          }
          .padding(.horizontal, 16)
          .padding(.top, 6)
        }
        .scrollIndicators(.hidden)
      }
    }
    .onAppear { page = items.first?.id }
  }

  private var files: some View {
    List {
      ForEach(items) { item in
        HStack(spacing: 12) {
          ZStack {
            RoundedRectangle(cornerRadius: 8).fill(SysColors.primary.opacity(0.12))
            Image(systemName: item.isVisual ? "photo" : "doc.fill")
              .foregroundStyle(SysColors.primary)
          }
          .frame(width: 40, height: 40)
          VStack(alignment: .leading, spacing: 2) {
            Text(item.fileURL.lastPathComponent).lineLimit(2)
            if let size = RoomViewModel.sizeText(item.size) {
              Text(size).font(.footnote).foregroundStyle(SysColors.textSecondary)
            }
          }
        }
        .swipeActions {
          Button("Remove", systemImage: "trash", role: .destructive) { remove(item) }
        }
      }
    }
  }

  private func removeButton(_ item: AttachmentLoader.Loaded) -> some View {
    Button {
      remove(item)
    } label: {
      Image(systemName: "xmark.circle.fill")
        .symbolRenderingMode(.palette)
        .foregroundStyle(.white, .black.opacity(0.6))
        .font(.system(size: 18))
    }
    .accessibilityLabel("Remove")
  }

  private func remove(_ item: AttachmentLoader.Loaded) {
    AttachmentLoader.remove(item)
    withAnimation { items.removeAll { $0.id == item.id } }
    if items.isEmpty {
      dismiss()
    } else if page == item.id {
      page = items.first?.id
    }
  }

  private var captionBar: some View {
    HStack(alignment: .bottom, spacing: 10) {
      TextField("Add a caption…", text: $caption, axis: .vertical)
        .lineLimit(1...4)
        .accessibilityIdentifier(A11yIdentifiers.room.attachmentCaption)
        .focused($isCaptionFocused)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(SysColors.surface, in: .rect(cornerRadius: 20))
      Button {
        let batch = items
        let text = caption
        let described = descriptions
        dismiss()
        Task { await viewModel.send(batch: batch, caption: text, descriptions: described) }
      } label: {
        Image(systemName: "arrow.up")
          .font(.system(size: 18, weight: .bold))
          .foregroundStyle(.white)
          .frame(width: 40, height: 40)
          .background(SysColors.primary, in: Circle())
      }
      .accessibilityLabel("Send")
      .accessibilityIdentifier(A11yIdentifiers.room.sendAttachments)
      .disabled(items.isEmpty)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
    .background(.bar)
  }
}

/// A picked picture, or a video's first frame, read from its local copy.
private struct LocalPreview: View {
  let item: AttachmentLoader.Loaded
  @State private var image: UIImage?

  var body: some View {
    ZStack {
      Color.black.opacity(0.04)
      if let image {
        Image(uiImage: image).resizable().scaledToFit()
      } else {
        ProgressView()
      }
      if case .video = item.kind {
        Image(systemName: "play.circle.fill")
          .font(.system(size: 36))
          .foregroundStyle(.white.opacity(0.9))
          .shadow(radius: 3)
      }
    }
    .task(id: item.id) { image = await item.previewImage() }
  }
}

extension AttachmentLoader.Loaded {
  /// A picture or a video.
  var isVisual: Bool {
    switch kind {
    case .image, .video: true
    default: false
    }
  }

  /// The picture itself, or a video's first frame.
  func previewImage() async -> UIImage? {
    switch kind {
    case .image:
      return UIImage(contentsOfFile: fileURL.path(percentEncoded: false))
    case .video:
      let generator = AVAssetImageGenerator(asset: AVURLAsset(url: fileURL))
      generator.appliesPreferredTrackTransform = true
      guard let frame = try? await generator.image(at: .zero).image else { return nil }
      return UIImage(cgImage: frame)
    default:
      return nil
    }
  }
}

/// "Alice is typing…" with three dots that bounce in turn, as iMessage and Telegram show it.
struct TypingIndicator: View {
  let text: String

  var body: some View {
    HStack(spacing: 8) {
      HStack(spacing: 4) {
        ForEach(0..<3, id: \.self) { index in
          Circle()
            .fill(SysColors.textSecondary)
            .frame(width: 6, height: 6)
            .phaseAnimator([0.0, 1.0]) { dot, phase in
              dot.offset(y: phase == 1 ? -3 : 0).opacity(phase == 1 ? 1 : 0.4)
            } animation: { _ in
              .easeInOut(duration: 0.45).delay(Double(index) * 0.15)
            }
        }
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 8)
      .background(SysColors.onPrimary, in: TwakeBubbleShape(isOwn: false))
      .shadow(color: .black.opacity(0.08), radius: 1)
      Text(text)
        .textStyle(TextStyles.bodySmall)
        .foregroundStyle(SysColors.textSecondary)
        .lineLimit(1)
      Spacer(minLength: 0)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 4)
    .accessibilityElement(children: .combine)
  }
}
