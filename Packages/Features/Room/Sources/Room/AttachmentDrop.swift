import DesignSystem
import Foundation
import SwiftUI
import UniformTypeIdentifiers

enum AttachmentDrop {
  static func fileType(offered: [UTType], isNamed: Bool) -> UTType? {
    let files = offered.filter { $0.conforms(to: .data) }
    if let media = files.first(where: { type in
      [UTType.image, .movie, .audio].contains { type.conforms(to: $0) }
    }) {
      return media
    }
    if let document = files.first(where: { !$0.conforms(to: .text) && !$0.conforms(to: .url) }) {
      return document
    }
    return isNamed ? files.first { !$0.conforms(to: .url) } : nil
  }

  static func fileName(suggested: String?, type: UTType) -> String {
    let trimmed =
      suggested?
      .replacingOccurrences(of: "/", with: "-")
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let base = trimmed.isEmpty ? UUID().uuidString : trimmed
    guard let wanted = type.preferredFilenameExtension else { return base }
    let current = URL(filePath: base).pathExtension
    if !current.isEmpty, UTType(filenameExtension: current)?.conforms(to: type) == true {
      return base
    }
    return "\(base).\(wanted)"
  }

  static func fileType(of provider: NSItemProvider) -> UTType? {
    fileType(offered: provider.registeredContentTypes, isNamed: provider.suggestedName != nil)
  }

  @MainActor
  static func load(
    _ providers: [NSItemProvider],
    then deliver: @escaping @MainActor ([AttachmentLoader.Loaded]) -> Void
  ) {
    let files = providers.compactMap { provider in
      fileType(of: provider).map { (provider, $0) }
    }
    guard !files.isEmpty else { return }
    let gathering = DropGathering(count: files.count, deliver: deliver)
    for (index, (provider, type)) in files.enumerated() {
      let name = fileName(suggested: provider.suggestedName, type: type)
      _ = provider.loadFileRepresentation(for: type, openInPlace: false) {
        @Sendable url, _, _ in
        let loaded = url.flatMap { stage($0, named: name) }
        Task { @MainActor in gathering.receive(loaded, at: index) }
      }
    }
  }

  static func stage(_ url: URL, named name: String) -> AttachmentLoader.Loaded? {
    let folder = FileManager.default.temporaryDirectory.appending(
      path: "dropped/\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: folder) }
    guard
      (try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true))
        != nil
    else { return nil }
    let named = folder.appending(path: name)
    guard (try? FileManager.default.copyItem(at: url, to: named)) != nil else { return nil }
    return AttachmentLoader.load(document: named)
  }
}

@MainActor
final class DropGathering {
  private var slots: [AttachmentLoader.Loaded?]
  private var remaining: Int
  private let deliver: @MainActor ([AttachmentLoader.Loaded]) -> Void

  init(count: Int, deliver: @escaping @MainActor ([AttachmentLoader.Loaded]) -> Void) {
    slots = Array(repeating: nil, count: count)
    remaining = count
    self.deliver = deliver
  }

  func receive(_ loaded: AttachmentLoader.Loaded?, at index: Int) {
    guard slots.indices.contains(index), remaining > 0 else { return }
    slots[index] = loaded
    remaining -= 1
    if remaining == 0 { deliver(slots.compactMap(\.self)) }
  }
}

extension RoomViewModel {
  var acceptsDroppedFiles: Bool {
    canSendMessages && !isSelectingMessages && !isArchived && successorLink == nil
      && blockedUserId == nil
  }
}

struct AttachmentDropDelegate: DropDelegate {
  let isEnabled: Bool
  @Binding var isTargeted: Bool
  let onDrop: ([NSItemProvider]) -> Void

  func validateDrop(info: DropInfo) -> Bool {
    isEnabled
      && info.itemProviders(for: [.item]).contains { AttachmentDrop.fileType(of: $0) != nil }
  }

  func dropEntered(info: DropInfo) {
    withAnimation(.easeOut(duration: 0.15)) { isTargeted = true }
  }

  func dropExited(info: DropInfo) {
    withAnimation(.easeOut(duration: 0.1)) { isTargeted = false }
  }

  func dropUpdated(info: DropInfo) -> DropProposal? {
    DropProposal(operation: .copy)
  }

  func performDrop(info: DropInfo) -> Bool {
    isTargeted = false
    guard isEnabled else { return false }
    let providers = info.itemProviders(for: [.item])
    guard providers.contains(where: { AttachmentDrop.fileType(of: $0) != nil }) else {
      return false
    }
    onDrop(providers)
    return true
  }
}

struct AttachmentDropModifier: ViewModifier {
  let viewModel: RoomViewModel
  @State private var isTargeted = false
  @State private var preview: PickedBatch?

  func body(content: Content) -> some View {
    content
      .onDrop(
        of: [.item],
        delegate: AttachmentDropDelegate(
          isEnabled: viewModel.acceptsDroppedFiles, isTargeted: $isTargeted
        ) { providers in
          AttachmentDrop.load(providers) { loaded in
            let loaded = viewModel.sendable(loaded)
            if !loaded.isEmpty { preview = PickedBatch(items: loaded) }
          }
        }
      )
      .overlay { DropVeil(isShown: isTargeted) }
      .sheet(item: $preview) { batch in
        SendPreviewSheet(items: batch.items, viewModel: viewModel)
      }
  }
}

struct DropVeil: View {
  let isShown: Bool

  var body: some View {
    RoundedRectangle(cornerRadius: 16)
      .strokeBorder(SysColors.primary, style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
      .background(SysColors.primary.opacity(0.08), in: .rect(cornerRadius: 16))
      .overlay {
        Text(localized("Drop to send"))
          .textStyle(TextStyles.titleMedium)
          .foregroundStyle(SysColors.primary)
      }
      .padding(8)
      .scaleEffect(isShown ? 1 : 0.98)
      .opacity(isShown ? 1 : 0)
      .allowsHitTesting(false)
      .accessibilityHidden(true)
  }
}

extension View {
  func attachmentDrop(_ viewModel: RoomViewModel) -> some View {
    modifier(AttachmentDropModifier(viewModel: viewModel))
  }
}
