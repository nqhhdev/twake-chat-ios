import DesignSystem
import Domain
import SwiftUI

/// The user's profile, edited as the iOS contact card: the picture with Edit (Choose Photo, Remove Photo), which
/// changes at once, and the display name, saved with Done.
struct EditProfileSheet: View {
  let viewModel: SettingsViewModel
  @Environment(\.dismiss) private var dismiss
  @State private var name = ""

  var body: some View {
    NavigationStack {
      Form {
        Section {
          PhotosAvatarPicker(
            name: viewModel.displayName, pictureID: viewModel.avatar?.source,
            load: viewModel.avatar.map { reference in
              { @Sendable [viewModel] in await viewModel.picture(reference) }
            },
            isWorking: viewModel.isUpdatingPicture,
            onPick: { picture in Task { await viewModel.setPicture(picture) } },
            onRemove: viewModel.avatar == nil
              ? nil : { Task { await viewModel.removePicture() } }
          )
          .frame(maxWidth: .infinity)
          .listRowBackground(Color.clear)
        }
        Section {
          TextField(localized("Display name"), text: $name)
            .textContentType(.name)
            .submitLabel(.done)
            .onSubmit { Task { await save() } }
        } header: {
          Text(localized("Name"))
        } footer: {
          Text(localized("Other people see this name and picture in chats."))
        }
        if let message = viewModel.errorMessage {
          Text(message).foregroundStyle(SysColors.error)
        }
      }
      .navigationTitle(localized("Edit Profile"))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(localized("Cancel")) { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button(localized("Done")) { Task { await save() } }
            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || viewModel.isWorking)
        }
      }
      .onAppear { name = viewModel.displayName }
    }
    .presentationDetents([.medium, .large])
  }

  /// Saves the name when it changed, then closes; a failed save stays open with the error.
  private func save() async {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed == viewModel.displayName {
      dismiss()
      return
    }
    if await viewModel.rename(to: trimmed) { dismiss() }
  }
}
