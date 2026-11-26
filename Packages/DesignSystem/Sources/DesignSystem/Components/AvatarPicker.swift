import SwiftUI

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
}

/// The large avatar of a profile or a chat with an "Edit" control under it, as the Contacts card. Choose Photo and
/// Remove Photo are shown here; the photo library itself is presented by the feature that owns this picker (ADR 0005:
/// DesignSystem imports only SwiftUI, so PhotosUI stays in the feature).
public struct AvatarPicker: View {
  private let name: String
  private let pictureID: String?
  private let load: (@Sendable () async -> Data?)?
  private let isWorking: Bool
  private let previewJPEG: Data?
  private let onRemove: (() -> Void)?
  @Binding private var isPickerShown: Bool

  /// - Parameters:
  ///   - previewJPEG: The picture just chosen, shown while it uploads.
  ///   - isPickerShown: Set to `true` when Choose Photo is tapped; the feature presents the photo library.
  ///   - onRemove: Removes the picture; `nil` hides Remove Photo (there is none).
  public init(
    name: String, pictureID: String?, load: (@Sendable () async -> Data?)?, isWorking: Bool,
    previewJPEG: Data?, isPickerShown: Binding<Bool>, onRemove: (() -> Void)?
  ) {
    self.name = name
    self.pictureID = pictureID
    self.load = load
    self.isWorking = isWorking
    self.previewJPEG = previewJPEG
    self.onRemove = onRemove
    _isPickerShown = isPickerShown
  }

  public var body: some View {
    VStack(spacing: 10) {
      ZStack {
        if let previewJPEG, isWorking, let preview = UIImage(data: previewJPEG) {
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
        Text(localized("Edit")).font(.subheadline.weight(.semibold))
          .padding(.horizontal, 14)
          .padding(.vertical, 5)
          .background(.fill.tertiary, in: .capsule)
      }
      .disabled(isWorking)
    }
    .accessibilityElement(children: .contain)
  }
}
