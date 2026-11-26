import DesignSystem
import Domain
import Observation
import SwiftUI

@MainActor @Observable
public final class NewSpaceViewModel: Identifiable {
  public var draft: NewSpace
  public private(set) var picture: PictureUpload?
  public private(set) var isCreating = false
  public private(set) var errorMessage: String?

  @ObservationIgnored private let repository: any SpacesRepository
  @ObservationIgnored private let onCreated: @MainActor (RoomSummary) -> Void

  public init(
    parentId: String? = nil, repository: any SpacesRepository,
    onCreated: @escaping @MainActor (RoomSummary) -> Void
  ) {
    draft = NewSpace(parentId: parentId)
    self.repository = repository
    self.onCreated = onCreated
  }

  public var isSubspace: Bool { draft.parentId != nil }

  public var canCreate: Bool { draft.canCreate && !isCreating }

  public func setPicture(jpeg: Data, side: Int) {
    picture = PictureUpload(data: jpeg, mimeType: "image/jpeg", width: side, height: side)
  }

  public func create() async {
    guard canCreate else { return }
    isCreating = true
    defer { isCreating = false }
    errorMessage = nil
    do {
      let roomId = try await repository.createSpace(draft, picture: picture)
      onCreated(
        RoomSummary(
          id: roomId, name: draft.trimmedName, lastMessageText: nil, lastMessageSender: nil,
          lastActivity: nil, isSpace: true, isPublic: draft.isPublic))
    } catch {
      errorMessage =
        isSubspace
        ? localized("Could not create the sub-space.") : localized("Could not create the space.")
    }
  }
}

struct NewSpaceScreen: View {
  @Bindable var viewModel: NewSpaceViewModel
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      Form {
        Section {
          PhotosAvatarPicker(
            name: viewModel.draft.trimmedName.isEmpty ? "?" : viewModel.draft.trimmedName,
            isWorking: viewModel.isCreating
          ) { prepared in
            viewModel.setPicture(jpeg: prepared.jpeg, side: prepared.side)
          }
          .frame(maxWidth: .infinity)
          .listRowBackground(Color.clear)
        }
        Section {
          TextField(localized("Name"), text: $viewModel.draft.name)
            .textInputAutocapitalization(.words)
            .accessibilityIdentifier(A11yIdentifiers.newSpace.name)
            .submitLabel(.done)
          TextField(
            localized("Description (optional)"), text: $viewModel.draft.topic, axis: .vertical
          )
          .lineLimit(1...4)
        }
        Section {
          Toggle(localized("Public"), isOn: $viewModel.draft.isPublic)
        } footer: {
          Text(visibilityFooter)
        }
        if let message = viewModel.errorMessage {
          Section { Text(message).foregroundStyle(SysColors.error) }
        }
      }
      .navigationTitle(viewModel.isSubspace ? localized("New Sub-space") : localized("New Space"))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(localized("Cancel")) { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          if viewModel.isCreating {
            ProgressView()
          } else {
            Button(localized("Create")) { Task { await viewModel.create() } }
              .disabled(!viewModel.canCreate)
              .accessibilityIdentifier(A11yIdentifiers.newSpace.create)
          }
        }
      }
      .interactiveDismissDisabled(viewModel.isCreating)
    }
  }

  private var visibilityFooter: String {
    if viewModel.draft.isPublic { return localized("Anyone on the server can find it and join.") }
    return viewModel.isSubspace
      ? localized("Members of the parent space can join it.")
      : localized("Only people you invite can join.")
  }
}
