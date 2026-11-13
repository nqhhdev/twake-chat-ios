import PhotosUI
import SwiftUI
import UIKit

/// An avatar picture made ready to upload: cut to the centre square and scaled down, as Contacts and Messages keep a
/// profile picture, so a full camera photo is not sent as an avatar.
public struct PreparedPicture: Equatable, Sendable {
  public let jpeg: Data
  public let side: Int

  /// The longest side of an avatar, in pixels.
  public static let maxSide: CGFloat = 512

  public init(jpeg: Data, side: Int) {
    self.jpeg = jpeg
    self.side = side
  }

  /// Cuts the picture in `data` to its centre square, at most `maxSide` pixels, as JPEG; `nil` when it is not a
  /// picture.
  public static func prepare(_ data: Data, maxSide: CGFloat = maxSide) -> PreparedPicture? {
    guard let image = UIImage(data: data) else { return nil }
    let pixels = CGSize(
      width: image.size.width * image.scale, height: image.size.height * image.scale)
    let square = min(pixels.width, pixels.height)
    guard square >= 1 else { return nil }
    let side = min(square, maxSide).rounded(.down)
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = true
    let rendered = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format)
      .image { _ in
        // Draw the whole picture scaled so its short side fills the square, centred.
        let scale = side / square
        let drawn = CGSize(width: pixels.width * scale, height: pixels.height * scale)
        image.draw(
          in: CGRect(
            x: (side - drawn.width) / 2, y: (side - drawn.height) / 2, width: drawn.width,
            height: drawn.height))
      }
    guard let jpeg = rendered.jpegData(compressionQuality: 0.85) else { return nil }
    return PreparedPicture(jpeg: jpeg, side: Int(side))
  }
}

/// The large avatar of a profile or a chat with an "Edit" control under it, as the Contacts card: Choose Photo opens
/// the photo library, Remove Photo appears when there is a picture. While a picture uploads, the avatar shows a
/// spinner.
public struct AvatarPicker: View {
  private let name: String
  private let pictureID: String?
  private let load: (@Sendable () async -> Data?)?
  private let isWorking: Bool
  private let onPick: (PreparedPicture) -> Void
  private let onRemove: (() -> Void)?

  @State private var item: PhotosPickerItem?
  @State private var isPickerShown = false
  @State private var preview: UIImage?

  /// - Parameters:
  ///   - onRemove: Removes the picture; `nil` hides Remove Photo (there is none).
  public init(
    name: String, pictureID: String?, load: (@Sendable () async -> Data?)?, isWorking: Bool,
    onPick: @escaping (PreparedPicture) -> Void, onRemove: (() -> Void)?
  ) {
    self.name = name
    self.pictureID = pictureID
    self.load = load
    self.isWorking = isWorking
    self.onPick = onPick
    self.onRemove = onRemove
  }

  public var body: some View {
    VStack(spacing: 10) {
      ZStack {
        if let preview, isWorking {
          // The chosen picture shows at once, while it uploads.
          Image(uiImage: preview).resizable().scaledToFill()
            .frame(width: 104, height: 104)
            .clipShape(Circle())
        } else {
          TwakeAvatar(name: name, size: 104, pictureID: pictureID, load: load)
        }
        if isWorking {
          Circle().fill(.black.opacity(0.35)).frame(width: 104, height: 104)
          ProgressView().tint(.white)
        }
      }
      .animation(.easeInOut(duration: 0.2), value: isWorking)
      Menu {
        Button("Choose Photo", systemImage: "photo.on.rectangle") { isPickerShown = true }
        if let onRemove {
          Button("Remove Photo", systemImage: "trash", role: .destructive, action: onRemove)
        }
      } label: {
        Text("Edit").font(.subheadline.weight(.semibold))
          .padding(.horizontal, 14)
          .padding(.vertical, 5)
          .background(.fill.tertiary, in: .capsule)
      }
      .disabled(isWorking)
    }
    .photosPicker(isPresented: $isPickerShown, selection: $item, matching: .images)
    .onChange(of: item) { _, picked in
      guard let picked else { return }
      item = nil
      Task {
        guard let data = try? await picked.loadTransferable(type: Data.self),
          let prepared = PreparedPicture.prepare(data)
        else { return }
        preview = UIImage(data: prepared.jpeg)
        onPick(prepared)
      }
    }
    .accessibilityElement(children: .contain)
  }
}
