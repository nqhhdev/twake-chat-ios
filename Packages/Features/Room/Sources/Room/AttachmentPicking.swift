import DesignSystem
import Domain
import Foundation
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// Turns what the pickers return into files the upload can read: pictures and videos from the photo library, and
/// documents from the Files app (iCloud Drive, Google Drive, Twake Drive or any other file provider). Each is copied into
/// a temporary folder of the app, so the upload never reads a security-scoped or remote URL.
enum AttachmentLoader {
  struct Loaded {
    let kind: OutgoingAttachment.Kind
    let fileURL: URL
    let mimeType: String?
    let size: Int?
  }

  /// A picture or a video from the photo library.
  static func load(_ item: PhotosPickerItem) async -> Loaded? {
    guard let data = try? await item.loadTransferable(type: Data.self) else { return nil }
    let type = item.supportedContentTypes.first ?? .jpeg
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
    let type = UTType(filenameExtension: url.pathExtension)
    let size = (try? copy.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
    let kind: OutgoingAttachment.Kind =
      if type?.conforms(to: .image) == true {
        .image(width: nil, height: nil)
      } else if type?.conforms(to: .movie) == true {
        .video(width: nil, height: nil, duration: nil)
      } else if type?.conforms(to: .audio) == true {
        .audio(duration: nil)
      } else {
        .file
      }
    return Loaded(kind: kind, fileURL: copy, mimeType: type?.preferredMIMEType, size: size)
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

/// The "+" of the Flutter composer (`chat_actions.dart` `PickerType`): Gallery and Documents. Each picked item is sent
/// on its own, so several pictures arrive together and show as an album.
struct AttachmentButton: View {
  let viewModel: RoomViewModel

  @State private var isGalleryShown = false
  @State private var isDocumentPickerShown = false
  @State private var pickedPhotos: [PhotosPickerItem] = []

  var body: some View {
    Menu {
      Button("Gallery", systemImage: "photo.on.rectangle") { isGalleryShown = true }
      Button("Documents", systemImage: "paperclip") { isDocumentPickerShown = true }
    } label: {
      Image(systemName: "plus")
        .font(.system(size: 20, weight: .semibold))
        .foregroundStyle(SysColors.primary)
        .frame(width: 40, height: 40)
        .background(SysColors.surface, in: Circle())
    }
    .accessibilityLabel("Attach")
    .photosPicker(
      isPresented: $isGalleryShown, selection: $pickedPhotos, maxSelectionCount: 10,
      matching: .any(of: [.images, .videos])
    )
    .onChange(of: pickedPhotos) { _, items in
      guard !items.isEmpty else { return }
      pickedPhotos = []
      Task {
        for item in items {
          guard let loaded = await AttachmentLoader.load(item) else { continue }
          await send(loaded)
        }
      }
    }
    .fileImporter(
      isPresented: $isDocumentPickerShown, allowedContentTypes: [.item],
      allowsMultipleSelection: true
    ) {
      result in
      guard case .success(let urls) = result else { return }
      Task {
        for url in urls {
          guard let loaded = AttachmentLoader.load(document: url) else { continue }
          await send(loaded)
        }
      }
    }
  }

  private func send(_ loaded: AttachmentLoader.Loaded) async {
    await viewModel.send(
      attachment: loaded.kind, fileURL: loaded.fileURL, mimeType: loaded.mimeType, size: loaded.size
    )
    AttachmentLoader.remove(loaded)
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
