import DesignSystem
import Domain
import SwiftUI

struct FilterChip: View {
  let title: String
  let isOn: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Text(title)
        .font(.subheadline.weight(.medium))
        .foregroundStyle(isOn ? SysColors.onPrimary : SysColors.onSurface)
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(isOn ? SysColors.primary : SysColors.surface, in: Capsule())
    }
    .buttonStyle(.borderless)
    .accessibilityAddTraits(isOn ? .isSelected : [])
  }
}

struct FolderEditorScreen: View {
  @Bindable var viewModel: FolderEditorViewModel
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      List {
        Section {
          HStack {
            TextField("😀" as String, text: $viewModel.emoji)
              .frame(width: 44)
              .multilineTextAlignment(.center)
              .accessibilityLabel(localized("Emoji"))
            TextField(localized("Folder name"), text: $viewModel.name)
              .textInputAutocapitalization(.words)
              .accessibilityIdentifier(A11yIdentifiers.folderEditor.name)
          }
        } footer: {
          if let error = viewModel.nameError {
            Text(error).foregroundStyle(SysColors.error)
          }
        }
        Section(localized("Include by kind")) {
          ForEach(Folder.ChatType.allCases, id: \.self) { type in
            Toggle(
              type.title,
              isOn: Binding(
                get: { viewModel.include.contains(type) },
                set: { viewModel.setIncluded(type, $0) }))
          }
        }
        Section(localized("Chats")) {
          ForEach(viewModel.chats) { chat in
            Button {
              viewModel.toggle(chat)
            } label: {
              HStack {
                Text(chat.name).foregroundStyle(SysColors.onSurface).lineLimit(1)
                Spacer()
                Image(systemName: viewModel.isPicked(chat) ? "checkmark.circle.fill" : "circle")
                  .foregroundStyle(
                    viewModel.isPicked(chat) ? SysColors.primary : SysColors.textSecondary)
              }
            }
            .accessibilityAddTraits(viewModel.isPicked(chat) ? .isSelected : [])
          }
        }
        if let message = viewModel.errorMessage {
          Text(message).foregroundStyle(SysColors.error)
        }
      }
      .searchable(text: $viewModel.query, prompt: localized("Search chats"))
      .navigationTitle(
        viewModel.previous == nil ? localized("New Folder") : localized("Edit Folder")
      )
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(localized("Cancel")) { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          if viewModel.isSaving {
            ProgressView()
          } else {
            Button(localized("Save")) { Task { await viewModel.save() } }
              .disabled(!viewModel.canSave)
              .accessibilityIdentifier(A11yIdentifiers.folderEditor.save)
          }
        }
      }
      .interactiveDismissDisabled(viewModel.isSaving)
    }
  }
}
