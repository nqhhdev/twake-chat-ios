import DesignSystem
import PhotosUI
import SwiftUI

/// `AvatarPicker` plus the photo library (PhotosUI). DesignSystem cannot import PhotosUI (ADR 0005).
struct PhotosAvatarPicker: View {
  private let name: String
  private let pictureID: String?
  private let load: (@Sendable () async -> Data?)?
  private let isWorking: Bool
  private let onPick: (PreparedPicture) -> Void
  private let onRemove: (() -> Void)?

  @State private var item: PhotosPickerItem?
  @State private var isPickerShown = false
  @State private var previewJPEG: Data?

  /// - Parameters:
  ///   - onRemove: Removes the picture; `nil` hides Remove Photo (there is none).
  init(
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

  var body: some View {
    AvatarPicker(
      name: name, pictureID: pictureID, load: load, isWorking: isWorking,
      previewJPEG: previewJPEG, isPickerShown: $isPickerShown, onRemove: onRemove
    )
    .photosPicker(isPresented: $isPickerShown, selection: $item, matching: .images)
    .onChange(of: item) { _, picked in
      guard let picked else { return }
      item = nil
      Task {
        guard let data = try? await picked.loadTransferable(type: Data.self),
          let prepared = PreparedPicture.prepare(data)
        else { return }
        previewJPEG = prepared.jpeg
        onPick(prepared)
      }
    }
  }
}
