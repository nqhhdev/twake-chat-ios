import DesignSystem
import PhotosUI
import SwiftUI

struct PhotosAvatarPicker: View {
  let name: String
  let isWorking: Bool
  let onPick: (PreparedPicture) -> Void

  @State private var item: PhotosPickerItem?
  @State private var isPickerShown = false
  @State private var previewJPEG: Data?

  var body: some View {
    AvatarPicker(
      name: name, pictureID: nil, load: nil, isWorking: isWorking, previewJPEG: previewJPEG,
      isPickerShown: $isPickerShown, onRemove: nil
    )
    .photosPicker(isPresented: $isPickerShown, selection: $item, matching: .images)
    .onChange(of: item) { _, picked in
      guard let picked else { return }
      item = nil
      Task {
        guard let data = try? await picked.loadTransferable(type: Data.self),
          let prepared = PreparedPicture.squared(data)
        else { return }
        previewJPEG = prepared.jpeg
        onPick(prepared)
      }
    }
  }
}
