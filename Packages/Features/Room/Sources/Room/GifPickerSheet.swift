import DesignSystem
import Domain
import ImageIO
import SwiftUI
import UIKit

extension GifPicker: Identifiable {}

struct GifPickerSheet: View {
  @State var picker: GifPicker
  let onPick: (Gif) -> Void
  @Environment(\.dismiss) private var dismiss

  private let columns = [GridItem(.adaptive(minimum: 104), spacing: 4)]

  var body: some View {
    NavigationStack {
      ScrollView {
        content
          .padding(.horizontal, 8)
      }
      .navigationTitle("GIFs")
      .navigationBarTitleDisplayMode(.inline)
      .searchable(
        text: $picker.query, placement: .navigationBarDrawer(displayMode: .always),
        prompt: picker.placeholder.isEmpty ? "Search GIFs" : picker.placeholder
      )
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
      }
      .task { await picker.start() }
    }
    .presentationDetents([.medium, .large])
  }

  @ViewBuilder private var content: some View {
    switch picker.phase {
    case .loading:
      ProgressView()
        .frame(maxWidth: .infinity, minHeight: 200)
    case .failed:
      ContentUnavailableView(
        "GIFs are not available right now", systemImage: "wifi.exclamationmark",
        description: Text("Try again later."))
    case .loaded where picker.gifs.isEmpty:
      ContentUnavailableView.search(text: picker.query)
    case .loaded:
      LazyVGrid(columns: columns, spacing: 4) {
        ForEach(picker.gifs) { gif in
          Button {
            dismiss()
            onPick(gif)
          } label: {
            AnimatedImage(url: gif.previewURL)
              .frame(height: 104)
              .frame(maxWidth: .infinity)
              .clipShape(.rect(cornerRadius: 8))
              .contentShape(.rect(cornerRadius: 8))
          }
          .buttonStyle(PressScaleButtonStyle())
          .accessibilityLabel(gif.title.isEmpty ? "GIF" : gif.title)
        }
      }
      if picker.next != nil {
        ProgressView()
          .frame(maxWidth: .infinity, minHeight: 44)
          .task(id: picker.gifs.count) { await picker.loadMore() }
      }
    }
  }
}

struct AnimatedImage: View {
  let url: URL
  @State private var image: UIImage?

  var body: some View {
    ZStack {
      Rectangle().fill(SysColors.surface)
      if let image {
        AnimatedImageView(image: image)
          .transition(.opacity)
      }
    }
    .task(id: url) {
      guard let (data, response) = try? await URLSession.shared.data(from: url),
        (response as? HTTPURLResponse)?.statusCode == 200
      else { return }
      let decoded = await Task.detached { AnimatedImageDecoder.image(from: data) }.value
      withAnimation(.easeOut(duration: 0.15)) { image = decoded }
    }
  }
}

struct AnimatedImageView: UIViewRepresentable {
  let image: UIImage
  var contentMode = UIView.ContentMode.scaleAspectFill

  func makeUIView(context: Context) -> UIImageView {
    let view = UIImageView()
    view.contentMode = contentMode
    view.clipsToBounds = true
    view.setContentHuggingPriority(.defaultLow, for: .horizontal)
    view.setContentHuggingPriority(.defaultLow, for: .vertical)
    view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
    return view
  }

  func updateUIView(_ view: UIImageView, context: Context) {
    view.image = image
    if image.images != nil { view.startAnimating() }
  }
}

enum AnimatedImageDecoder {
  static let defaultFrameDelay = 0.1

  static func image(from data: Data) -> UIImage? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
    let count = CGImageSourceGetCount(source)
    guard count > 1 else { return UIImage(data: data) }
    var frames: [UIImage] = []
    var duration: TimeInterval = 0
    for index in 0..<count {
      guard let frame = CGImageSourceCreateImageAtIndex(source, index, nil) else { continue }
      frames.append(UIImage(cgImage: frame))
      duration += frameDelay(source, at: index)
    }
    guard !frames.isEmpty else { return nil }
    return UIImage.animatedImage(with: frames, duration: duration)
  }

  static func frameDelay(_ source: CGImageSource, at index: Int) -> TimeInterval {
    guard
      let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil)
        as? [CFString: Any]
    else { return defaultFrameDelay }
    let dictionaries = [
      properties[kCGImagePropertyGIFDictionary] as? [CFString: Any],
      properties[kCGImagePropertyWebPDictionary] as? [CFString: Any],
      properties[kCGImagePropertyPNGDictionary] as? [CFString: Any],
    ]
    let keys = [
      kCGImagePropertyGIFUnclampedDelayTime, kCGImagePropertyGIFDelayTime,
      kCGImagePropertyWebPUnclampedDelayTime, kCGImagePropertyWebPDelayTime,
      kCGImagePropertyAPNGUnclampedDelayTime, kCGImagePropertyAPNGDelayTime,
    ]
    for dictionary in dictionaries.compactMap(\.self) {
      for key in keys {
        if let delay = (dictionary[key] as? NSNumber)?.doubleValue, delay > 0.011 {
          return delay
        }
      }
    }
    return defaultFrameDelay
  }
}
