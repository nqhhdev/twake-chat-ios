import Domain
import SwiftUI
import UIKit

extension RoomViewModel {
  static let emotePixels = 96

  func loadEmotes() async {
    emotes = await repository.emotes()
  }

  func emoteImage(_ source: String) -> UIImage? {
    emoteImages[source]
  }

  func loadEmoteImage(_ source: String) async {
    guard emoteImages[source] == nil, emoteLoads.insert(source).inserted else { return }
    defer { emoteLoads.remove(source) }
    let reference = MediaReference(source: source, mimeType: "image/*")
    guard
      let data = try? await media.thumbnail(
        reference, width: Self.emotePixels, height: Self.emotePixels),
      let image = await Task.detached(operation: { AnimatedImageDecoder.image(from: data) }).value
    else { return }
    emoteImages[source] = image
  }

  static func emoteSources(in text: AttributedString) -> [String] {
    var seen = Set<String>()
    return text.runs.compactMap { $0[EmoteAttribute.self] }.filter { seen.insert($0).inserted }
  }
}

struct EmoteImage: View {
  let source: String
  let viewModel: RoomViewModel
  let side: CGFloat

  var body: some View {
    Group {
      if let image = viewModel.emoteImage(source) {
        AnimatedImageView(image: image, contentMode: .scaleAspectFit)
      } else {
        Color.clear
      }
    }
    .frame(width: side, height: side)
    .task(id: source) { await viewModel.loadEmoteImage(source) }
  }
}

struct EmoteText: View {
  let text: AttributedString
  let viewModel: RoomViewModel
  @ScaledMetric(relativeTo: .body) private var side: CGFloat = 22

  var body: some View {
    composed
      .task(id: text) {
        for source in RoomViewModel.emoteSources(in: text) {
          await viewModel.loadEmoteImage(source)
        }
      }
  }

  private var composed: Text {
    var result = Text(verbatim: "")
    for run in text.runs {
      let piece: Text
      if let source = run[EmoteAttribute.self], let image = viewModel.emoteImage(source) {
        piece = Text(Image(uiImage: Self.resized(image, side: side)))
          .accessibilityLabel(String(text[run.range].characters))
      } else {
        piece = Text(AttributedString(text[run.range]))
      }
      result = Text("\(result)\(piece)")
    }
    return result
  }

  static func resized(_ image: UIImage, side: CGFloat) -> UIImage {
    let size = image.size
    guard size.width > 0, size.height > 0 else { return image }
    let scale = side / max(size.width, size.height)
    let target = CGSize(width: size.width * scale, height: size.height * scale)
    let still = image.images?.first ?? image
    return UIGraphicsImageRenderer(size: target).image { _ in
      still.draw(in: CGRect(origin: .zero, size: target))
    }
  }
}
