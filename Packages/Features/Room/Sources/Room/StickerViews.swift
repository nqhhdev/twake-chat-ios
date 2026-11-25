import DesignSystem
import Domain
import SwiftUI
import UIKit

struct StickerPickerSheet: View {
  let packs: [StickerPack]
  let repository: any MediaRepository
  let onPick: (Sticker) -> Void
  @Environment(\.dismiss) private var dismiss

  private let columns = [GridItem(.adaptive(minimum: 80), spacing: 8)]

  var body: some View {
    NavigationStack {
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 16) {
          ForEach(packs) { pack in
            Section {
              LazyVGrid(columns: columns, spacing: 8) {
                ForEach(pack.stickers) { sticker in
                  Button {
                    dismiss()
                    onPick(sticker)
                  } label: {
                    StickerImage(media: sticker.media, repository: repository)
                      .frame(width: 80, height: 80)
                      .contentShape(Rectangle())
                  }
                  .buttonStyle(PressScaleButtonStyle())
                  .accessibilityLabel(sticker.body)
                }
              }
            } header: {
              Text(pack.name)
                .textStyle(TextStyles.labelLarge)
                .foregroundStyle(SysColors.textSecondary)
            }
          }
        }
        .padding(16)
      }
      .navigationTitle("Stickers")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
      }
    }
    .presentationDetents([.medium, .large])
  }
}

struct StickerImage: View {
  let media: MediaReference
  let repository: any MediaRepository
  @State private var image: UIImage?

  var body: some View {
    ZStack {
      if let image {
        AnimatedImageView(image: image, contentMode: .scaleAspectFit)
          .transition(.opacity)
      } else {
        ProgressView()
      }
    }
    .task(id: media) {
      guard let data = try? await repository.content(media) else { return }
      let decoded = await Task.detached { AnimatedImageDecoder.image(from: data) }.value
      withAnimation(.easeOut(duration: 0.15)) { image = decoded }
    }
  }
}

struct StickerMessage: View {
  let message: TimelineMessage
  let media: MediaReference
  let repository: any MediaRepository

  static let side: CGFloat = 160

  static func size(of media: MediaReference) -> CGSize {
    let ratio = media.aspectRatio ?? 1
    return ratio >= 1
      ? CGSize(width: side / ratio, height: side) : CGSize(width: side, height: side * ratio)
  }

  var body: some View {
    VStack(alignment: message.isOwn ? .trailing : .leading, spacing: 2) {
      let size = Self.size(of: media)
      StickerImage(media: media, repository: repository)
        .frame(width: size.width, height: size.height)
        .accessibilityElement()
        .accessibilityLabel(Text("Sticker \(Self.text(of: message))"))
      Text(message.date, format: .dateTime.hour().minute())
        .textStyle(TextStyles.labelSmall)
        .foregroundStyle(SysColors.textSecondary)
    }
  }

  static func text(of message: TimelineMessage) -> String {
    if case .sticker(let text) = message.body { text } else { "" }
  }
}
